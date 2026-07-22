# Notes from Claude...
Here's what's in the zip and why it's structured this way:

bootstrap/main.tf — run this exactly once before anything else. It creates the S3 bucket and DynamoDB lock table using local state (no backend block), because you need those resources to exist before you can configure a remote backend that points to them. That's the classic chicken-and-egg problem with remote state.

modules/environment/ — the reusable core. You never terraform apply in here directly. Every resource has a comment explaining the "why" not just the "what," since that's what'll come up in interviews.

environments/dev|staging|prod/main.tf — each one is intentionally short. All the complexity lives in the module; these files just pass different values. Notice three things that differ per environment: the key path in the backend (dev/terraform.tfstate vs staging/... vs prod/...) — this is how each environment gets its own isolated state file in the same S3 bucket; the VPC CIDRs don't overlap (10.0, 10.1, 10.2) so you could VPC-peer them later if needed; and SSH access tightens progressively from wide open in dev to VPC-internal only in prod.

The ssm_command_example output is a nice touch to have — after terraform apply it prints a ready-to-run SSM command for that specific instance ID, which ties directly back to the fleet script you built in Week 2.


# Terraform Environment Module

Parameterized AWS environment provisioner: VPC + subnets + IGW + NAT + route tables + security group + IAM role + EC2 instance. One module, three environments — dev/staging/prod each get isolated state with DynamoDB locking.

## Project structure

```
terraform/
├── bootstrap/          # Run once — creates the S3 bucket and DynamoDB lock table
│   └── main.tf
├── modules/
│   └── environment/    # The reusable module — never call this directly
│       ├── main.tf     # All resource definitions
│       ├── variables.tf
│       └── outputs.tf
└── environments/
    ├── dev/            # Calls the module with dev sizing/access
    ├── staging/        # Calls the module with staging sizing/access
    └── prod/           # Calls the module with prod sizing/access
```

## First-time setup

### Step 1 — Bootstrap (once only)

Creates the S3 bucket and DynamoDB table that store and lock all environment state:

```bash
cd bootstrap/
terraform init
terraform apply
# Note the output values — you'll paste them into each environment's backend block
```

### Step 2 — Update backend config

In each `environments/*/main.tf`, replace the placeholder values:

```hcl
backend "s3" {
  bucket         = "myproject-terraform-state-YOUR_ACCOUNT_ID"  # from bootstrap output
  dynamodb_table = "myproject-terraform-locks"                   # from bootstrap output
  ...
}
```

### Step 3 — Deploy an environment

```bash
cd environments/dev/
terraform init      # Configures the S3 backend and downloads providers
terraform plan      # Shows what will be created — review before applying
terraform apply     # Creates the infra; prompts for confirmation
```

## How locking works in practice

When `terraform apply` runs:

1. Terraform writes a lock record to DynamoDB: `{ LockID: "s3-bucket/dev/terraform.tfstate" }`
2. Any other apply that starts while the lock exists fails immediately with an error like:
   ```
   Error: Error acquiring the state lock
   Lock Info:
     ID: 12345678-...
     Who: tim@laptop
     Created: 2026-07-15 10:23:01
   ```
3. When apply finishes, the lock record is deleted automatically

If a lock gets stuck (e.g. your laptop died mid-apply):
```bash
terraform force-unlock <lock-id>
```

## Per-environment differences

| Setting          | dev         | staging      | prod                    |
|-----------------|-------------|--------------|-------------------------|
| Instance type   | t3.micro    | t3.small     | t3.medium               |
| VPC CIDR        | 10.0.0.0/16 | 10.1.0.0/16  | 10.2.0.0/16             |
| SSH access      | 0.0.0.0/0   | Office CIDR  | VPC only (use SSM)      |
| State key       | dev/...     | staging/...  | prod/...                |
| Root volume     | 20GB        | 20GB         | 50GB (set in module)    |

## Verify your instance is reachable via SSM

After apply, use the output command directly:

```bash
# The ssm_command_example output prints a ready-to-run command:
aws ssm send-command \
  --instance-ids i-XXXXXXXXXXXXXXXXX \
  --document-name AWS-RunShellScript \
  --parameters commands='uptime && df -h' \
  --region us-east-1 \
  --query "Command.CommandId" \
  --output text

# Then fetch the output with the command ID:
aws ssm get-command-invocation \
  --command-id <command-id> \
  --instance-id i-XXXXXXXXXXXXXXXXX \
  --query "StandardOutputContent" \
  --output text
```

This is the modern equivalent of your MCollective fleet commands — no SSH required.

## Tear down

```bash
cd environments/dev/
terraform destroy   # Destroys all resources in this environment only
                    # Other environments are untouched (separate state files)
```


