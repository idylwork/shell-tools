
# 用例: .zshrcファイルに組み込み
# [ -f ~/.zsh/index.sh ] && source ~/.zsh/index.sh

# シェルの設定読み込み
[ -f ~/.zsh/src/settings.sh ] && source ~/.zsh/src/settings.sh

# Toolスクリプトの読み込み
[ -f ~/.zsh/src/tool.sh ] && source ~/.zsh/src/tool.sh

# ワークスペースに移動する
# スペース区切りでディレクトリを深掘り
ws() {
  to ws $@
}
