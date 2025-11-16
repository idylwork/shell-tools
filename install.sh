# Toolスクリプトのインストール

(
profile_path="${HOME}/.zshrc"
install_dir="${HOME}/.zsh"
index_path="${install_dir}/index.sh"
source_dir=$(dirname $0)

TEXT_DANGER="\x1b[31m%s\n\x1b[m"
TEXT_SUCCESS="\x1b[32m%s\n\x1b[m"

# パスのホームディレクトリをチルダに変換
tilde_path () {
  echo "${1/$HOME/~}"
}

# すでにフォルダが存在すれば中止
if [ -e ${install_dir} ]; then
  printf $TEXT_DANGER "Tool script is already installed. ($(tilde_path ${install_dir}))"
  exit 1
fi

# Homebrewがインストールされていなければ中止
if ! command -v brew >/dev/null 2>&1; then
  printf $TEXT_DANGER "Homebrew is not installed. Please install it from https://brew.sh"
  exit 1
fi

# ソースファイルをコピー
printf $TEXT_SUCCESS "Copying script source... ($(tilde_path ${install_dir}))"
cp -r ${source_dir} ${install_dir}

# 設定ファイルを初期化
sample_dir="${install_dir}/sample/config"
config_dir="${install_dir}/config"
printf $TEXT_SUCCESS "Initializing configuration files... ($(tilde_path ${config_dir}))"
sample_paths=($(ls ${sample_dir}/*.sample))
for sample_path in "${sample_paths[@]}"; do
  config_name=$(basename "${sample_path}" ".sample")
  cp "${sample_path}" "${config_dir}/${config_name}"
done

# プロファイルへの書き込み
printf $TEXT_SUCCESS "Updating profile. ($(tilde_path ${profile_path}))"
index_tilde_path=$(tilde_path ${index_path})
echo "# Toolスクリプトの読み込み\n[ -f ${index_tilde_path} ] && source ${index_tilde_path}" >> ~/.zshrc

# Homebrewによる依存ライブラリのインストール
printf $TEXT_SUCCESS "Installing dependencies via Homebrew..."
brew install volta

printf $TEXT_SUCCESS "Installation successful."
source ${index_path}
)
