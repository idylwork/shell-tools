# SleepWatcher
#
# @usage
# ## インストールとデーモン化
# ```bash
# brew install sleepwatcher
# brew services start sleepwatcher
# ln -s ~/.zsh/utilities/sleep.sh ~/.sleep
# ```
#
# ## アンインストール
# ```bash
# brew services stop sleepwatcher
# brew uninstall sleepwatcher
# unlink ~/.sleep
# ```

(
# NPM 開発サーバーの停止
pid=$(lsof -t -i:3000)
if [ -z "${pid}" ]; then
    exit 0
fi
kill -INT ${pid}
)
