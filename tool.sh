## sh emulation mode
#emulate -R sh

# Required brew packages: rmtrash gh
to() {
# 引数とオプションを取得 ${args[1]}: 引数1 $options['somekey']: オプション(値指定なしで1)
local -a args=()
local -A options=()
for i in $(seq $#); do
  local arg=${${@}[$i]}
  case $arg in
    --*)
      local option_text=${arg#--}
      [[ ${option_text} == *=* ]] && options[${option_text%=*}]=${option_text#*=} || options[${option_text}]=1
      ;;
    -* )
      local option_text=${arg#-}
      [[ ${option_text} == *=* ]] && options[${option_text%=*}]=${option_text#*=} || options[${option_text}]=1
      ;;
    * )
      [ -z "$action" ] && local action=${arg} || args+=${arg}
    ;;
  esac
done

# スクリプト定数
local -r WORKSPACE="${HOME}/Workspace"
local -r BROWSER="/Applications/Safari.app"
local -r BROWSER_ALT="Google Chrome"
local -r DEST_DIR="${WORKSPACE}/dist"
local -r IMPORT_DIR="${HOME}/.zsh"
local -r EXPORT_DIR="${HOME}/Dropbox/Settings/Shell/zsh"
local -r TOOL_SCRIPT="${IMPORT_DIR}/tool.sh"
local -r WORKSPACE_SCRIPT="${IMPORT_DIR}/workspace.sh"
local -r WORKSPACE_INI="${IMPORT_DIR}/workspace.ini"
local -r BRANCH_INI="${IMPORT_DIR}/branch.ini"
local -r MAX_PROJECT_CONSTANTS_COUNT=30

# 出力文字色
local -r COLOR_WARNING="\e[33m%s\n\e[m"
local -r COLOR_DANGER="\e[31m%s\n\e[m"
local -r COLOR_NOTICE="\e[35m%s\n\e[m"
local -r COLOR_SUCCESS="\e[32m%s\n\e[m"
local -r COLOR_INFO="\e[35m%s\n\e[m"
local -r COLOR_INFO_DARK="\e[34m%s\n\e[m"
local -r COLOR_MUTED="\e[2m%s\n\e[m"

# Load ini file section
load_ini() {
  # Default constants
  local section=$(grep "-A${MAX_PROJECT_CONSTANTS_COUNT}" "\[default\]" ${WORKSPACE_INI} | sed -e '1d' | sed -n '/^\[.*\]$/q;p' | sed 's/ *= */=/g')
  source <(grep = <(grep "-A${MAX_PROJECT_CONSTANTS_COUNT}" "\[default\]" ${WORKSPACE_INI} | sed -e '1d' | sed -n '/^\[.*\]$/q;p' | sed 's/ *= */=/g'))

  # Project constants
  if [ $# = 0 ]; then
    source <(grep = ${WORKSPACE_INI} | sed 's/ *= */=/g')
  else
    local section=$(grep "-A${MAX_PROJECT_CONSTANTS_COUNT}" "\[$1\]" ${WORKSPACE_INI} | sed -e '1d' | sed -n '/^\[.*\]$/q;p' | sed 's/ *= */=/g')
    source <(grep = <(grep "-A${MAX_PROJECT_CONSTANTS_COUNT}" "\[$1\]" ${WORKSPACE_INI} | sed -e '1d' | sed -n '/^\[.*\]$/q;p' | sed 's/ *= */=/g'))
    [ "${section}" = "" ] && printf $COLOR_MUTED 'No workspace configuration found.'
  fi
}
# Key Press in Safari
browser_keydown() {
    osascript -e "tell application \"${BROWSER}\" to activate" -e "tell application \"System Events\" to keystroke $1"
}
# Input text in Safari
browser_input() {
    browser_keydown "\"$1\""
}
# Input text in Safari
browser_input_halfwidth() {
    browser_input "$1"
    browser_keydown '"a" using option down'
    if [ -z "$2" ]; then
      browser_keydown "return"
    else
      browser_keydown "return&$2"
    fi
}
# Check exclude file exists in dest dir
check_config_exists() {
  [ -e "${DEST_DIR}/config" ] || [ -e "${DEST_DIR}/dist/vagrant" ] && echo 1
}
# Vagrantfileのディレクトリに移動
cd_vagrant() {
  cd "${VAGRANT_DIR}" > /dev/null 2>&1
}
# 仮想マシンのファイルを監視する
watch_vm_file() {
  case $2 in
  '' ) local call='';;
  -c ) local call='| ccze -A' || local call='';;
  * )
    local call=''
    for word in ${@:2}
    do
      if [[ "$word" =~ ^sed ]]; then
        local sed=`echo ${word} | sed -e 's/^sed //'`
        [ -e $is_sed ] && local call="${call} | sed -e '${sed}'" || local call="${call} -e '${sed}'"
        printf $COLOR_INFO_DARK "[SED] ${sed}"
        local is_sed=true
      else
        local call="${call} | grep --line-buffered '${word}'"
        printf $COLOR_INFO_DARK "[GREP] ${word}"
      fi
    done
    printf $COLOR_INFO_DARK $call
    ;;
  esac

  # / が含まれなければ自動的に/var/logを見る
  [[ $1 =~ '/' ]] && local log_file="$1" || local log_file="/var/log/$1"
  printf $COLOR_INFO "Start Watching '${log_file}'..."


  if [ "$VM_PLATFORM" = "vagrant" ]; then
    cd_vagrant
    vagrant ssh -c "tail -f ${log_file} ${call}"
  else
    docker compose exec web bash -c "tail -f ${log_file} ${call}"
  fi
}

# ブラウザでサイトを開く [1]URL [2]DomainType [3]--alt
# --alt : 別ブラウザで開く
open_in_browser() {
  local browser=$BROWSER
  if [ "$3" = '--alt' ] || [ "$2" = '--alt' ]; then
    local browser=$BROWSER_ALT
  fi

  case $2 in
  production|p ) local domain="${DOMAIN_PRODUCTION}" ;;
  staging|s ) local domain="${DOMAIN_STAGING}" ;;
  * )
    local domain="$(get_local_domain)"
    echo $domain
  esac

  [ $domain ] && open -a $browser "${domain}$1"
}

# Search pull requests by branch numbers
open_git_pulls() {
  local remote_params=$(git remote -v | sed -n -e 1p)
  if [[ $remote_params =~ '^origin.*https://' ]]; then
    local url=$(echo $remote_params | grep -oe "https://.*\.git" | sed "s|\.git|/${query}|")
  else
    local url="https://github.com/$(echo $remote_params | grep -oe "[a-zA-Z-]*/.*\.git" | sed "s|\.git|/${query}|")"
  fi

  local query="pulls?q=is%3Apr"
  if [ $# = 0 ]; then
    query+="+is%3Aopen"
  elif [ "$1" = "current" ]; then
    local query="pull/$(git rev-parse --abbrev-ref HEAD)"
  elif [ $# = 1 ]; then
    local query="pull/${BRANCH_PREFIX}$1"
  else
    for branch_num in $@; do
      query+="+head%3A${BRANCH_PREFIX}${branch_num}"
    done
  fi
  echo "${url}/${query}"
  open -a $BROWSER "${url}/${query}"
}

# ローカル開発環境のドメインを出力する
get_local_domain() {
  local ip="$(grep '.vm.network :private_network, ip: "*"' ${VAGRANT_DIR}Vagrantfile | grep -o '\d\+.\d\+.\d\+.\d\+')"

  if [ -z "$ip" ]; then
    local ip="$(grep '.vm.network \"private_network\", ip: \"*\"' ${VAGRANT_DIR}Vagrantfile | grep -o '\d\+.\d\+.\d\+.\d\+')"

  fi
  [ "$LOCAL_SSH_PROTOCOL" = "true" ] && local protocol='https' || local protocol='http'

  echo "${protocol}://${ip}"
}

# ヘルプメッセージを表示する
# - action: 限定するアクション名
print_help() {
  [ -n "$1" ] && local prefix="\[$1" || local prefix=""
  printf $COLOR_SUCCESS "──────────────────────"
  printf $COLOR_SUCCESS " Presonal Tool Script "
  printf $COLOR_SUCCESS "──────────────────────"
  cat $TOOL_SCRIPT | grep "^\s*#\{2,\} ${prefix}" | grep -v '^\s*## sh' | sed -e "s/^ *#\{3,\} /  /g" | sed -e "s/^ *## //g" |
    sed -e "s/^\( *-\{1,2\}[a-z][a-z-]*\)\(.*\)/  \x1b[36;1;9m\1\x1b[0m\x1b[36;9m\2\x1b[0m/g" | # オプションを書式調整
    sed -e "s/\[\(.*\)\]/\x1b[33;1;9m\1\x1b[0m/g" # []を着色
}

# --help オプションが指定された場合はヘルプメッセージを表示する
if [[ -n "${options[help]}" ]]; then
  print_help $action
  return
fi

# プロジェクト定数 (Workspace直下か.gitのあるディレクトリをルートとする)
local workspace_dir=$(pwd | sed -e "s|${WORKSPACE}/\([^/]*\).*$|\1|")
if [[ "$workspace_dir" != $(basename $(pwd)) ]] && [ -e ".git" ]; then
  local PROJECT_NAME=$(basename $(pwd))
  local PROJECT_DIR=$(pwd)
  echo $PROJECT_NAME $PROJECT_DIR
else
  local PROJECT_NAME=$(pwd | sed -e "s|${WORKSPACE}/\([^/]*\).*$|\1|")
  local PROJECT_DIR="${WORKSPACE}/${PROJECT_NAME}/"
fi
unset workspace_dir
local -r VAGRANT_DIR="${PROJECT_DIR}/vagrant/"
[ "$PROJECT_NAME" = "${WORKSPACE}" ] && PROJECT_NAME='workspace'
load_ini $PROJECT_NAME

# Actions
case $action in

## [test] 設定値のチェック
test )
  printf $COLOR_INFO "Project:"
  echo "  ${PROJECT_NAME}\n"

  printf $COLOR_INFO "Properties:"
  grep "-A${MAX_PROJECT_CONSTANTS_COUNT}" "\[${PROJECT_NAME}\]" ${WORKSPACE_INI} | sed -e '1d' | sed -n '/^\[.*\]$/q;p' | sed 's/ *= */=/g'
  echo ""

  printf $COLOR_INFO "Arguments:"
  for arg in ${args}; do
    echo "  ${arg}"
  done
  echo ""

  printf $COLOR_INFO "Options:"
  for option_key in "${(k)options[@]}"; do
    echo "  ${option_key} = ${options[${option_key}]}"
  done
  echo ""
;;

## [sync] スクリプトと設定ファイルをエクスポートする
sync )
  case $args[1] in
  ### [sync import] スクリプトと設定ファイルをインポートする
  import )
    printf $COLOR_WARNING "シェルスクリプトの設定ファイルを上書きインポートしますか？ (y/n)"
    read answer
    if [ "$answer" = "y" ]; then
      rsync -r $EXPORT_DIR $IMPORT_DIR --exclude='.DS_Store'
      printf $COLOR_WARNING "シェルスクリプトを読み込みました"
      printf $COLOR_WARNING "初回のみ.zshrcへの組み込みが必要です"
      printf "${EXPORT_DIR} > ${IMPORT_DIR}"
    fi
    ;;
  * )
    rsync -r $IMPORT_DIR $EXPORT_DIR --exclude='.DS_Store'
    printf $COLOR_WARNING "シェルスクリプトを保存しました"
    printf "${IMPORT_DIR} > ${EXPORT_DIR}"
  esac
;;

## [bash] Dockerに接続してシェルを起動
bash )
  [ ${args[1]} ] && local container=${args[1]} || local container='web'
  printf $COLOR_INFO_DARK "Start connecting on ${container}..."
  docker compose exec ${container} bash
;;

## [edit] スクリプトと設定の編集
edit )
  printf $0
  code -n $IMPORT_DIR
;;

## [refresg] スクリプトと設定の変更を反映
refresh )
  source $TOOL_SCRIPT
  printf $COLOR_SUCCESS "Tool script is refreshed."
;;

## [git] Gitクライアントを開く
git )
  local git_client_path='/Applications/Sourcetree.app'
  local remote_params=$(git remote -v | sed -n -e 1p)
  if [[ $remote_params =~ '^origin.*https://' ]]; then
    local url=$(echo $remote_params | grep -oe "https://.*\.git" | sed "s|\.git|/${query}|")
  else
    local url="https://github.com/$(echo $remote_params | grep -oe "[a-zA-Z-]*/.*\.git" | sed "s|\.git|/${query}|")"
  fi

  case $args[1] in
  ### [git] リポジトリの状況をアプリケーションで表示
  ''|tree|t )
    printf $COLOR_INFO 'Start openning repository on git client…'
    open -a $git_client_path $PROJECT_DIR
    ;;
  ### [git i] GitHubのIssuesページを開く
  issue|is|i )
    open -a $BROWSER "${url}/issues"
    ;;
  ### [git p] GitHubのPull sRequestsページを開く
  pulls|pr|p )
    open_git_pulls ${@:3}
    ;;
  ### [git pull] アップストリームを指定してリモートブランチをプルする
  pull )
    case $args[2] in
    "" )
      # ブランチ指定なしで現在ブランチをプル
      local branch_name=$(git rev-parse --abbrev-ref HEAD)
      git branch --set-upstream-to=origin/${branch_name} ${branch_name} > /dev/null 2>&1
      git pull
      ;;
    [0-9]* )
      # 数値のみ指定でデフォルトブランチ
      git fetch
      git checkout -b ${BRANCH_PREFIX}$2 "origin/${BRANCH_PREFIX}$2"
      ;;
    * )
      git fetch
      git checkout -b $args[2] "origin/$args[2]"
    esac
    ;;
  ### [git forcepull] リモートブランチでローカルブランチを上書きする
  forcepull )
    local branch_name=$(git rev-parse --abbrev-ref HEAD)
    local base_commit=$(git merge-base ${BASE_BRANCH} HEAD)
    git log --oneline --graph $base_commit..HEAD

    printf $COLOR_DANGER "Would you like to overwrite ${branch_name}? (y/n)"
    read answer

    if [ "$answer" = "y" ]; then
      git fetch origin
      git reset --hard "origin/${branch_name}"
    fi
    ;;
  ### [git sweep] マージされたブランチlogを一括削除
  ### --all ベースブランチを除外したすべてのブランチを対象とする
  sweep )
    if [[ -n "${options[all]}" ]]; then
      local branches=$(git branch --merged | egrep -v "main|master|develop|staging|stg|dev|\* ")
    else
      local branches=$(git branch --merged | egrep -v "main|master|\* " | egrep "${BRANCH_PREFIX}|issue|fix|feature")
    fi
    if [ -n "$branches" ]; then
      printf "${branches}\n"
      printf $COLOR_WARNING "Would you like to remove merged branches? (y/n)"
      read answer
      if [ "$answer" = "y" ]; then
        if [[ -n "${options[all]}" ]]; then
          git branch --merged | egrep -v "main|master|stg|dev" | xargs git branch -d
        else
          git branch --merged | egrep "${BRANCH_PREFIX}|issue|fix|feature" | xargs git branch -d
        fi
        printf $COLOR_SUCCESS "Merged branches removed!"
      fi
    else
      printf $COLOR_WARNING "No merged branch."
    fi
    ;;
  ### [git amend] 現在ステージ中のファイルを前のコミットに追加コミットする
  amend )
    local message=$(git log --oneline | head -n 1 | sed "s|^[a-z0-9]* ||")
    printf $COLOR_WARNING $message
    git status --short
    printf $COLOR_WARNING "Would you like to override previous commit? (y/n)"
    read answer
    if [ "$answer" = "y" ]; then
      git commit --amend -m $message
    fi
  ;;
  * )
    open -a $BROWSER ${url}
  esac
;;

## [<number>] 番号から規定のブランチをチェックアウトする
[0-9]* )
  git checkout ${BRANCH_PREFIX}$1
;;

## [-] 前のブランチをチェックアウトする
- )
  echo $action
  git checkout ${action}
;;

## [open] Webサイトのホームを開く
open )
  open_in_browser "${URL_FRONT}" ${@:2}
;;

## [admin] Webサイトの管理画面を開く
admin )
  open_in_browser "${URL_ADMIN}" ${@:2}
;;

## [telescope] Laravel Telescopeをブラウザで開く
telescope )
  open_in_browser "/telescope/queries" ${@:2}
;;

## [diff] ベースブランチからの差分を確認
## --copy 出力内容をクリップボードにコピーする
### [diff main] メインブランチの最新コミットの差分を確認
### [diff copy] 出力内容をクリップボードにコピーする
diff )
  case $args[1] in
  master|main )
    local target="$args[1]..$args[1]~1"
    ;;
  copy )
    local base_commit=$(git merge-base ${BASE_BRANCH} HEAD)
    local target="${base_commit}..HEAD"
    options[copy]="1"
    ;;
  * )
    local base_commit=$(git merge-base ${BASE_BRANCH} HEAD)
    local target="${base_commit}..HEAD"
    ;;
  esac

  local file_changes=$(git diff --name-only --diff-filter=MAR ${target})
  if [ -z "$file_changes" ]; then
    printf $COLOR_DANGER "差分ファイルがありません"
    return
  fi

  printf $COLOR_INFO "$(echo $file_changes | grep -c '') files changed. (${target})"
  printf "${file_changes}\n"

  if [[ -n "${options[copy]}" ]]; then
    echo ${file_changes} | pbcopy
    printf $COLOR_SUCCESS "差分ファイルリストをクリップボードにコピーしました"
  fi
;;

## [dist] 差分ファイルをdist出力する
## --with-config 設定ファイルを含める
## --commit 直前のコミットのみ
dist )
  local base_commit=$(git merge-base ${BASE_BRANCH} HEAD)
  cd "${WORKSPACE}/${PROJECT_NAME}/" > /dev/null 2>&1

  case $args[1] in
  ### [dist ls] ファイル確認
  ls )
    printf $COLOR_WARNING "distフォルダを表示します"
    tree -a "${DEST_DIR}"
    ;;
  ### [dist copy] 実行せずコマンドをコピーする
  copy )
    git diff --name-only --diff-filter=MAR ${base_commit}..HEAD | xargs -I {} echo "rsync -R {}  ${DEST_DIR}" | pbcopy
    printf $COLOR_WARNING "${BASE_BRANCH}ブランチからの差分ファイル出力用rsyncコマンドをコピーしました"
    ;;
  ### [dist rm] ファイル削除
  rm | * )
    # ファイル操作ありのコマンド
    rm -rf ${DEST_DIR} > /dev/null 2>&1
    mkdir ${DEST_DIR}

    case $2 in
      rm )
        printf $COLOR_WARNING "distフォルダを削除しました"
        ;;
      --with-config )
        git diff --name-only --diff-filter=MAR ${base_commit}..HEAD | xargs -I {} rsync -R {} ${DEST_DIR}
        printf $COLOR_WARNING "${BASE_BRANCH}ブランチからの差分ファイルをdistフォルダにコピーしました (設定ファイルを含む)"
        ;;
      --commit|-c )
        git diff --name-only --diff-filter=MAR HEAD^..HEAD | xargs -I {} rsync -R {} ${DEST_DIR}
        printf $COLOR_WARNING "直前のコミットの変更をdistフォルダにコピーしました"
        ;;
      * )
        git diff --name-only --diff-filter=MAR ${base_commit}..HEAD | grep -vE ^app/config | xargs -I {} rsync -R {}  ${DEST_DIR}
        printf $COLOR_WARNING "${BASE_BRANCH}ブランチからの差分ファイルをdistフォルダにコピーしました"
        ;;
      esac
    cd -
    ;;
    esac
;;

## [deploy] ファイルリリースで管理しているサーバーにdistフォルダをリリースする
##        デフォルトでステージングサーバー
## -y デプロイ前の確認をスキップする
deploy )
  [ $2 ] && env=$2 || env="staging"
  case $env in
    ### [deploy production] 本番サーバーにdistフォルダをリリースする (未実装)
    production )
      # /tmpディレクトリ固定のためファイルパスチェックなし
      ;;
    ### [deploy staging] ステージングサーバーにdistフォルダをリリースする
    staging )
      [ -v $DEPLOY_TO ] && printf $COLOR_DANGER "Deploy path is not configured. (${env})" && return
      ;;
  esac

  tree $DEST_DIR

  if check_config_exists; then
    printf $COLOR_WARNING "設定ファイルが含まれています！"
  else
    [ "$env" = "production" ] && printf $COLOR_DANGER "- DEPLOY TO PRODUCTION !!"
    if [ "$2" = "-y" ]; then
      local answer="y"
    else
      printf $COLOR_WARNING "Would you like to deploy under dist to ${env}? (y/n)"
      read answer
    fi
  fi

  case $answer in
    y)
      case $env in
        production )
          # 本番はtmpにアップロード
          rsync -hrv "${DEST_DIR}/${DEPLOY_DIR}" "${SSH_NAME_PRODUCTION}:/tmp/releases/$(date +%Y%m%d)" --exclude='.DS_Store'
          ;;
        staging )
          # ステージングは直接アップロード
          rsync -hrvop "${DEST_DIR}/${DEPLOY_DIR}" "${SSH_NAME_STAGING}:${DEPLOY_TO}" --exclude='.DS_Store'
          ;;
      esac

      printf $COLOR_SUCCESS "Deployed!"
      ;;
    *) ;;
  esac
;;

## [build] リリースファイルを作成する (未メンテナンス)
build )
  rm -rf ${DEST_DIR} > /dev/null 2>&1
  mkdir ${DEST_DIR}
  base_commit="master"
  release_commit="$BASE_BRANCH"

  case $2 in
  ## --copy 実行せずコマンドをコピーする
  --copy )
    git diff --name-only --diff-filter=MAR ${base_commit}..${release_commit} | xargs -I {} echo "rsync -R {}  ${DEST_DIR}" | pbcopy
    printf $COLOR_WARNING "${BASE_BRANCH}ブランチからの差分ファイル出力用rsyncコマンドをコピーしました"
    ;;
  *)
    git diff --name-only --diff-filter=MAR ${base_commit}..${release_commit} | grep -vE ^app/config | xargs -I {} rsync -R {}  ${DEST_DIR}
    zip -r "${DEST_DIR}/${BACKLOG_PREFIX}.zip" "${DEST_DIR}/${DEPLOY_DIR}"
    printf $COLOR_WARNING "${BASE_BRANCH}ブランチからの差分ファイルをdistフォルダにコピーしました"
    ;;
  esac
;;

## [ssh | ssh <environment>] SSH接続してアプリケーションルートに移動する
ssh )
  case $args[1] in
  ### [ssh staging] 接続先を指定する
  staging|s )
    #[ -v SSH_NAME_STAGING ] && printf $COLOR_DANGER "SSH name is not configured. (${env})" && return
    printf $COLOR_SUCCESS "Connecting to ${PROJECT_NAME} [staging]... (${APP_ROOT})"
    ssh ${SSH_NAME_STAGING} -t "cd ${APP_ROOT}; bash --login"
    ;;
  *)
    printf $COLOR_SUCCESS "Connecting to ${PROJECT_NAME} [locat]... (${APP_ROOT})"
    cd_vagrant
    vagrant ssh -c 'cd "/var/www/$(ls /var/www | more)"; bash --login'
    ;;
  esac
;;

## [vagrant] Vagrantを切り替え
vagrant )
  cd_vagrant
  case $args[1] in
  ### [vagrant init] Vagrantシステム設定ファイルの更新
  init )
    print "Vagrant環境のシステム設定ファイルを更新しました"
    vagrant ssh -c "{
      echo \"set -o noclobber\"
      echo \"cd ${APP_ROOT}\"
    } >> ~/.bashrc"
    ;;
  ### [vagrant down] すべてのVagrantを停止する
  down|* )
    vagrant global-status | grep 'virtualbox running' | sed 's|^\([^ ]*\).*|\1|' | xargs -I {} vagrant suspend {}

    # to vagrant down 再起動せず全停止させる
    if [ "$2" != 'down' ]; then
      vagrant up
    fi
    ;;
  esac
  cd -
;;

## [db] VagrantのSQLに接続する
db )
  cd_vagrant
  vagrant ssh -c "psql ${PSQL_OPTIONS}"
;;

## [aws] プロジェクト名をプロファイル名としてAWS CLIを使用する
aws )
  aws --profile ${PROJECT_NAME} ${@:2}
;;

## [log] ログファイルを表示する
log )
  case $args[1] in
  production|p ) local domain="${DOMAIN_PRODUCTION}" ;;
  staging|s )
    ssh -t ${SSH_NAME_STAGING} "tail -f ${LOG_PRODUCTION}"| ccze -A
    ;;
  * )
    [ $# = 2 ] && local filepath="$2" || local filepath="${LOG_LOCAL}"
    watch_vm_file "${filepath}"
  esac
;;

## [bl] Backlogに関する操作
bl )
  [ -v $BACKLOG_PREFIX ] && printf $COLOR_DANGER "Backlog prefix is not configured." && return

  case $2 in
  ### [bl <0-9>] 課題を開く
  [0-9]* )
    open "https://hotfactory.backlog.jp/view/${BACKLOG_PREFIX}-$2"
    ;;
  ### [set <project_id>] Backlog課題番号とブランチ名の対応リストを追加する
  set )
    # ブランチ名と課題番号が一致しない場合は`to bl set ${project_id}`で紐付け可能
    if [ "$BACKLOG_TASK_ID_BRANCH_NAME" = "true" ]; then
      echo "ブランチ名から課題検索できるプロジェクトです"
    elif expr "$3" : "[0-9]*" >& /dev/null; then
      local branch_name=$(git rev-parse --abbrev-ref HEAD)
      sed -i".org" -e "/backlog_${PROJECT_NAME}_${branch_name} = /d" $BRANCH_INI
      echo "backlog_${PROJECT_NAME}_${branch_name} = ${BACKLOG_PREFIX}$3" >> $BRANCH_INI
      echo "課題番号を登録しました。[${branch_name} → ${BACKLOG_PREFIX}$3]"
    else
      echo "課題番号を指定してください"
    fi
    ;;
  * )
    local branch_name=$(git rev-parse --abbrev-ref HEAD)
    local key="backlog_${PROJECT_NAME}_${branch_name}"
    local task_id="$(grep $key ${BRANCH_INI} | sed 's/^.* *= *//g')"

    if [ "$branch_name" = "master" ] || [ "$branch_name" = "$BASE_BRANCH" ]; then
      # ベースブランチ
      printf $COLOR_INFO_DARK "Open backlog project"
      open "https://hotfactory.backlog.jp/find/${BACKLOG_PREFIX}"
    elif [ "$task_id" != "" ]; then
      # iniに設定されたブランチ
      printf $COLOR_INFO_DARK "Open backlog task ${task_id}"
      open "https://hotfactory.backlog.jp/view/${task_id}"
    elif [ "$BACKLOG_TASK_ID_BRANCH_NAME" = "true" ]; then
      # ブランチ名と課題名が同じプロジェクト
      open "https://hotfactory.backlog.jp/view/${branch_name}"
    else
      echo '課題番号の登録がありません'
      open "https://hotfactory.backlog.jp/find/${BACKLOG_PREFIX}"
    fi
    ;;
  esac
;;

## [master|main|staging|stg|develop|dev] ベースブランチのチェックアウト
master|main|staging|stg|develop|dev|$BASE_BRANCH )
  echo $action
  git checkout ${action}
  git pull
;;

## [new <branch_name>] 新しいブランチを作成してチェックアウトする
new )
  if expr "$2" : "[0-9]*" >& /dev/null; then
    local branch_name="${BRANCH_PREFIX}$2"
  else
    local branch_name="$2"
  fi
  git checkout -b ${branch_name} >& /dev/null
  echo "ブランチ『${branch_name}』を作成しました"
;;

## [forcepull] リモートブランチでローカルブランチを上書きする
forcepull )
  local branch_name=$(git rev-parse --abbrev-ref HEAD)
  local base_commit=$(git merge-base ${BASE_BRANCH} HEAD)
  git log --oneline --graph $base_commit..HEAD

  printf $COLOR_DANGER "Would you like to overwrite ${branch_name}? (y/n)"
  read answer

  if [ "$answer" = "y" ]; then
    git fetch origin
    git reset --hard "origin/${branch_name}"
  fi
;;

## [pmlog] システムのスリープ履歴を表示
pmlog )
  if [[ -n "${options[display]}" ]]; then
    printf $COLOR_INFO 'スリープの解除と蓋の開閉時間'
    pmset -g log | grep -e 'Charge' -e 'Display is turned' -e 'Entering Sleep' -e 'Wake from'
  else
    printf $COLOR_INFO 'スリープの解除時間'
    pmset -g log | grep -e 'Entering Sleep' -e 'Wake from'
  fi
;;

## [..] プロジェクトルートに移動
.. )
  cd $PROJECT_DIR
;;

## [ws <directory>] プロジェクトルートに移動する 引数分ディレクトリを深掘りして曖昧検索する
ws )
  if [ -z $args ]; then
    cd $WORKSPACE > /dev/null 2>&1
    ls
  else
    local project_path=$WORKSPACE
    local project_name=""

    for arg in ${args}; do
      local prefix_regex="^${arg}.*"
      local fuzzy_regex="^$(echo ${arg} | sed 's|.|&.*|g')"

      # まず前方一致で確認、一致がない場合はあいまい検索で検索で再検索
      local target_dir=$(ls $project_path | grep -s -m1 $prefix_regex)
      if [ -z target_dir ]; then
        target_dir=$(ls $project_path | grep -s -m1 $fuzzy_regex)
      fi
      project_name=$target_dir
      project_path+="/${target_dir}"
    done

    cd $project_path > /dev/null 2>&1
    printf "\e[35m%s\n\e[m" "Project: ${project_name}"
  fi
;;

## [help] ヘルプメッセージを表示
help )
  print_help
;;

## [<etc>] プロジェクト別のアクションを workspace.sh から読み込み
* )
  [ -f $WORKSPACE_SCRIPT ] && source $WORKSPACE_SCRIPT
esac # Actions
}
