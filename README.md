# Self-hosted zrok on ECS/EC2 (single-AZ, low-cost)

Terraform to run a self-hosted [zrok](https://zrok.io) instance (the "zrok2"
release) as a **single ECS/EC2 task** on AWS — one small `t4g.small` box, one AZ,
a public HTTPS endpoint with an automatic wildcard TLS cert. Optimized for
functionality and low cost, not high availability.

zrok self-hosting is a self-contained stack (its own OpenZiti overlay + Postgres)
and ships only as a Docker Compose project. This repo translates that stack 1:1
into a single ECS task and stands up the supporting AWS resources.

## Architecture

One ECS task (`bridge` networking, container `links` for the `ziti.`/`router.`/
`zrok2.` aliases, `dependsOn` for init ordering) on a single container instance:

| Container | Role | Public port |
|-----------|------|-------------|
| `ziti-controller` | OpenZiti control plane | 1280 (direct mTLS) |
| `ziti-router-init` | one-shot: create edge router + JWT | — |
| `ziti-router` | OpenZiti data plane | 3022 (direct TLS) |
| `postgresql` | zrok datastore | — |
| `rabbitmq` | dynamic-frontend name resolution (required) | — |
| `zrok2-init` | one-shot: bootstrap PKI, frontend, namespace | — |
| `zrok2-controller` | zrok API | — (behind Caddy) |
| `zrok2-frontend` | public share dynamic proxy | — (behind Caddy) |
| `caddy` | TLS termination, Route53 DNS-01 | 443 |

- **Endpoints:** `https://zrok2.<dns_zone>` (API) and `https://*.<dns_zone>`
  (shares), via an Elastic IP + wildcard Route53 record.
- **State:** Docker-managed named volumes on the instance's EBS (mirror the compose
  named volumes). Bootstrap scripts are fetched by instance user-data.
- **TLS:** Caddy (prebuilt image with the Route53 plugin, pushed to ECR) obtains a
  wildcard cert via the Route53 DNS challenge, authorized by the ECS task role — no
  static keys.

## Prerequisites

- An AWS account + credentials (profile or default chain), Terraform ≥ 1.5.
- A public **Route53 hosted zone** you own, for `dns_zone`.
- Docker with `buildx` (to build/push the Caddy image, one time).
- A VPC and one public subnet (the stack adds a public route table if the subnet
  lacks internet egress).

## Deploy

1. **Build & push the Caddy image** (once) to an ECR repo `zrok2/caddy-route53`:

   ```bash
   ACCT=<ACCOUNT_ID>; REGION=us-east-2
   REG=$ACCT.dkr.ecr.$REGION.amazonaws.com
   aws ecr create-repository --repository-name zrok2/caddy-route53 || true
   aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $REG
   docker buildx build --platform linux/arm64 -f Dockerfile.caddy \
     -t $REG/zrok2/caddy-route53:latest --push .
   ```

2. **Set variables** — copy `terraform/terraform.tfvars.example` to
   `terraform/terraform.tfvars` and fill in `dns_zone`, `hosted_zone_id`,
   `vpc_id`, `subnet_id` (and `profile` if used). This file is gitignored.

3. **Create the secrets** in SSM Parameter Store (SecureString) before apply:

   ```bash
   for p in ZITI_PWD ZROK2_ADMIN_TOKEN ZROK2_DB_PASSWORD; do
     aws ssm put-parameter --name /zrok2/$p --type SecureString \
       --value "$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 40)" --overwrite
   done
   ```

   > The `terraform/ssm.tf` params use `ignore_changes = [value]`, so Terraform
   > manages the parameters without ever overwriting their live values.

4. **Apply:**

   ```bash
   cd terraform
   terraform init
   terraform plan -out=tfplan
   terraform apply tfplan
   ```

5. **Create the first account** once the task is `HEALTHY`:

   ```bash
   TASK=$(aws ecs list-tasks --cluster zrok2 --query 'taskArns[0]' --output text)
   aws ecs execute-command --cluster zrok2 --task "$TASK" \
     --container zrok2-controller --interactive \
     --command "zrok2 admin create account you@example.com <password>"
   # Save the printed enable token.
   ```

6. **Use it from a workstation:**

   ```bash
   export ZROK2_API_ENDPOINT=https://zrok2.<dns_zone>
   zrok2 enable <token>
   zrok2 create name mytest
   zrok2 share public http://127.0.0.1:8080 --name-selection public:mytest
   # → reachable at https://mytest.<dns_zone>/
   ```

## Operate

```bash
aws ecs describe-tasks --cluster zrok2 --tasks <TASK_ID> \
  --query 'tasks[0].containers[].{name:name,health:healthStatus,last:lastStatus}' --output table
aws logs tail /ecs/zrok2 --follow
```

## Two non-obvious things this stack handles

1. **Subnet internet egress.** A subnet tagged "public" may still lack a default
   route to the IGW (it inherits a local-only main route table). The stack creates
   a dedicated public route table + `0.0.0.0/0 → IGW` + association (`network.tf`).
2. **Ziti router volume permissions.** `ziti-router-init` runs as root, writes the
   enrollment JWT into `/ziti-router`, and `chown`s it to uid 2171 so the non-root
   `ziti-router` can write its config/certs (`scripts/ziti-router-init.sh`).

## Cost (~$18–20/mo, on-demand, us-east-2)

`t4g.small` (~$12) + 30 GB gp3 (~$2.4) + 1 public IPv4 (~$3.65) + CloudWatch logs
(~$0.5). ECS control plane and SSM Standard are free. A 1-yr Savings Plan on the
instance cuts it to ~$14/mo. Single instance, single AZ = **no HA** by design.

## Teardown

```bash
cd terraform && terraform destroy
```
