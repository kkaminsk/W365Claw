## 1. Update Documentation

- [x] 1.1 Replace `terraform destroy` in README.md Quick Start with targeted teardown guidance
- [x] 1.2 Update outputs.tf next_steps to document targeted resource removal instead of blanket destroy
- [x] 1.3 Update README.md Cost section to reference the teardown script

## 2. Create Teardown Script

- [x] 2.1 Create `scripts/Teardown-BuildResources.ps1` that removes AIB template resources via Terraform state rm + az resource delete
