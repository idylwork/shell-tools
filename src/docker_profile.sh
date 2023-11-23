alias art=$(artisan_path=$(find . -maxdepth 2 -type f -name artisan); [ $artisan_path ] && echo $artisan_path || echo "echo Laravel artisan not found.")
