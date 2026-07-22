# Terraform architecture diagram

```mermaid
flowchart TD
    subgraph "1. Bootstrap"
        B[bootstrap/main.tf]
        S3[(S3 bucket for remote state)]
        DDB[(DynamoDB lock table)]
        B --> S3
        B --> DDB
    end

    subgraph "2. Environment entrypoints"
        DEV[environments/dev/main.tf]
        STAGE[environments/staging/main.tf]
        PROD[environments/prod/main.tf]
    end

    subgraph "3. Shared module"
        MOD[modules/environment/main.tf]
    end

    subgraph "4. AWS resources created by the module"
        VPC[aws_vpc]
        SUBNETS[aws_subnet public/private]
        IGW[aws_internet_gateway]
        NAT[aws_nat_gateway]
        SG[aws_security_group]
        IAM[aws_iam_role + instance profile]
        KEY[aws_key_pair + tls_private_key]
        EC2[aws_instance]
    end

    DEV --> MOD
    STAGE --> MOD
    PROD --> MOD

    MOD --> VPC
    MOD --> SUBNETS
    MOD --> IGW
    MOD --> NAT
    MOD --> SG
    MOD --> IAM
    MOD --> KEY
    MOD --> EC2

    DEV --> S3
    STAGE --> S3
    PROD --> S3

    DEV --> DDB
    STAGE --> DDB
    PROD --> DDB

    VPC --> SUBNETS
    SUBNETS --> SG
    SG --> EC2
    IAM --> EC2
    KEY --> EC2
```

## How it fits together

1. Bootstrap creates the shared S3 bucket and DynamoDB table for remote state and locking.
2. Each environment directory (dev, staging, prod) calls the same shared module.
3. The shared module builds a complete environment stack: networking, security, IAM, key pair, and EC2.
4. Terraform uses the S3 backend to store state and the DynamoDB lock table to prevent two applies from running at the same time.

## Beginner version

Think of this setup like a template plus three small projects:

- The bootstrap step is like setting up the shared storage room.
- Each environment folder is like a different room you want to build: dev, staging, and prod.
- The module is the instruction book that tells Terraform how to build one room.
- Terraform reads the instructions, creates the AWS resources, and saves the results in S3.

In simple terms:

- Dev, staging, and prod each ask for the same kind of environment.
- The shared module makes sure they are built the same way.
- The bootstrap step makes sure Terraform has a safe place to store its state.
- The EC2 instance is the actual server that gets created in AWS.
