chmod +x scripts/*.sh

./scripts/init.sh dev
./scripts/plan.sh dev
./scripts/apply.sh dev



How to use scripts/pre_apply_check.sh
chmod +x pre_apply_check.sh
./pre_apply_check.sh dev


Use w3m to View Your HTML Report
w3m reports/pre_apply_check.html or
lynx reports/pre_apply_check.html




# How to use scripts/validate_post_apply.sh
chmod +x scripts/destroy-plan.sh
./scripts/destroy-plan.sh dev


Destroying infr:

# Step 1: Review and save a destroy plan
chmod +x scripts/destroy.sh
./scripts/destroy-plan.sh dev

# Step 2: Apply it
chmod +x scripts/destroy.sh
./scripts/destroy.sh dev

# destroy checks
chmod +x scripts/validate_post_destroy.sh
./scripts/validate_post_destroy.sh


# Bash script that recursively walks through your Terraform project folder, and creates a single output text file with:
    A number for each file
    The relative path
    The full content of the file

 The file is in root directory and file name is generate_tf_summary.sh
Make it executable:

chmod +x generate_tf_summary.sh

./generate_tf_summary.sh
It will generate a terraform_code_summary.txt file in the same directory.
