# Bash command initialize by tool script
alias art=$(laravel_path=$(find $(pwd) -maxdepth 1 -type d -name laravel); [ $laravel_path ] && echo "${laravel_path}/artisan" || echo "echo Laravel not found.")
