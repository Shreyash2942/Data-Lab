# Terraform Layer

Terraform CLI 1.7 ships in the container for quick infrastructure demos. Project files live under `~/terraform` (mirrors `repo_root/terraform`) and store their working state in `~/runtime/terraform`.

## Layout

| Path | Purpose |
| --- | --- |
| `terraform/main.tf` | Sample configuration (modify or replace with your own). |
| `terraform/variables.tf`, `terraform/outputs.tf` | Optional helpers depending on your setup. |
| `~/runtime/terraform` | Houses `terraform.tfstate`, `.terraform` plugin cache, etc. Safe to delete to reset. |

## Running the demo

Inside the container:

```bash
export TF_DATA_DIR=~/runtime/terraform/.terraform
terraform -chdir=~/terraform init
terraform -chdir=~/terraform apply -auto-approve -state=~/runtime/terraform/terraform.tfstate
```

When finished, destroy resources (if applicable):

```bash
terraform -chdir=~/terraform destroy -auto-approve -state=~/runtime/terraform/terraform.tfstate
```

Menu helper: `bash ~/app/services_demo.sh --run-terraform-demo` (option `7`), which runs `init` + `apply` with the correct state paths.

## Notes

- Environment variables such as `AWS_PROFILE`, `GOOGLE_APPLICATION_CREDENTIALS`, etc., can be exported before running Terraform if you point at external providers.
- Never commit `runtime/terraform`—it is already ignored; remove it to reset the demo quickly.

## Resources

- Official docs: https://developer.hashicorp.com/terraform/docs
