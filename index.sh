
# 用例: .zshrcファイルに組み込み
# [ -f ~/.zsh/index.sh ] && source ~/.zsh/index.sh

# Toolスクリプトの読み込み
[ -f ~/.zsh/tool.sh ] && source ~/.zsh/tool.sh

# ワークスペースに移動する
# スペース区切りでディレクトリを深掘り
ws() {
  to ws $@
}

# Docker
alias doc='docker compose'
docsh() {
  [ $@ ] && local container=$@ || local container='web'
  docker compose exec ${container} bash
}

# Vagrant
vc() {
  cd vagrant > /dev/null 2>&1
  if [ $# ]; then
    vagrant ssh -c "$*"
  fi
}
alias vgs='vagrant global-status'
alias vsweep="vagrant global-status | grep 'virtualbox running' | sed 's|^\([^ ]*\).*|\1|' | xargs -I {} vagrant suspend {}"
