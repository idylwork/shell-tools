## sh emulation mode
#emulate -R sh

# toコマンドの定義

to() {
# 定数の読み込み
source ~/.zsh/src/constants.sh

# 関数の読み込み
source $FUNCTIONS_PATH

# 引数とオプションを取得 ${args[1]}: 引数1 ${args[some_key]}: オプション(指定なしで値は1)
# $optionsは順次$argsに統一していく
local action=$1
local -A args=($(parse_arguments ${@:2}))
local -A options=(${(kv)args})
unset arguments_all

# --help オプションが指定された場合はヘルプメッセージを表示して完了
if [[ -n "${options[help]}" ]]; then
  print_help $action
  return
fi

# プロジェクト定数
local -r PROJECT_DIR=$(get_project_root)
local -r PROJECT_NAME=$(basename ${PROJECT_DIR})
local -r VAGRANT_DIR="${PROJECT_DIR}/vagrant/"
source <(parse_ini ${SCRIPT_DIR}/config/projects.ini --section=default | sed "s/^ */local /g")
source <(parse_ini ${SCRIPT_DIR}/config/projects.ini --section=${PROJECT_NAME} | sed "s/^ */local /g")

# アクションを実行する
case $action in

## [test] 設定値のチェック
test )
  local project_ini="${SCRIPT_DIR}/config/projects.ini"
  if [[ "$(pwd)" == "${WORKSPACE}" ]]; then
    printf $TEXT_INFO "Projects:"

    local ini_sections=($(grep -E "^\[.*\]$" ${project_ini} | sed "s/^\[//" | sed "s/\]$//"))

    # INIに設定されているプロジェクトの一覧
    for ini_section in ${ini_sections[@]}; do
      if [[ "${ini_section}" == "default" ]]; then
        continue
      fi

      if [ -d ${WORKSPACE}/${ini_section} ]; then
        echo "  ${ini_section}"
      else
        local target_project_dir=$(find ${WORKSPACE} -type d -maxdepth 2 -name ${ini_section} | sed "s|${WORKSPACE}||" 2> /dev/null)
        if [ -n "$target_project_dir" ]; then
          echo "  ${target_project_dir:1}"
        else
          printf $TEXT_MUTED "  ${ini_section}"
        fi
      fi
    done
    echo ""
  else
    printf $TEXT_INFO "Project:"
    echo "  ${PROJECT_NAME}\n"
  fi

  # defaultセクションからキーを取得して全プロジェクト定数を表示
  printf $TEXT_INFO "Properties:"
  local prop_names=($(parse_ini ${project_ini} --section=default | sed 's/^\(.*\)=.*/\1/'))
  for prop_name in "${prop_names[@]}"; do
    echo "  ${prop_name}=$(eval echo \${${prop_name}})"
  done
  echo ""

  printf $TEXT_INFO "Arguments:"
  for arg_key in "${(k)args[@]}"; do
    echo "  ${arg_key} = ${args[${arg_key}]}"
  done
  echo ""
;;

## [sync] スクリプトと設定ファイルをエクスポートする
sync )
  case $args[1] in
  ### [sync import] スクリプトと設定ファイルをインポートする
  import )
    printf $TEXT_WARNING "シェルスクリプトの設定ファイルを上書きインポートしますか？ (y/n)"
    printf $TEXT_WARNING "${EXPORT_DIR} > ${SCRIPT_DIR}"
    read answer
    if [ "$answer" = "y" ]; then
      rsync -rcv "${EXPORT_DIR}/" $SCRIPT_DIR --exclude='.DS_Store' --exclude='/.git' -C --filter=":- .gitignore"
      printf $TEXT_SUCCESS "シェルスクリプトを読み込みました"
      printf $TEXT_SUCCESS "初回のみ.zshrcへの組み込みが必要です"
    fi
    ;;
  ### [sync ls] 反映中スクリプトの確認
  ls )
    ls -lohpTSG $SCRIPT_DIR
    ;;
  * )
    printf $TEXT_WARNING "シェルスクリプトの設定ファイルをエクスポートしますか？ (y/n)"
    printf $TEXT_WARNING "${SCRIPT_DIR} > ${EXPORT_DIR}"
    read answer
    if [ "$answer" = "y" ]; then
      rsync -rcv "${SCRIPT_DIR}/" $EXPORT_DIR --exclude='.DS_Store' --exclude='/.git' -C --filter=":- .gitignore"
      printf $TEXT_SUCCESS "シェルスクリプトを保存しました"
    fi
  esac
;;

## [bash] Dockerに接続してシェルを起動
bash )
  [ ${args[1]} ] && local container=${args[1]} || local container='web'
  printf $TEXT_INFO_DARK "Start connecting on ${container}... (docker compose exec -it ${container} bash)"
  docker compose exec -it ${container} bash
;;

## [note] メモファイルの表示
note )
  local note_file="${SCRIPT_DIR}/note.txt"
  case $args[1] in
  edit )
    vi ${note_file}
    ;;
  * )
    printf $TEXT_SUCCESS "──────────────────────"
    printf $TEXT_SUCCESS "     Script Note      "
    printf $TEXT_SUCCESS "──────────────────────"
    cat ${note_file}
    echo ""
  esac
;;

## [doc] Docker関連のコマンド
doc|docker )
  case $args[1] in
  ### [doc restart] Dockerを強制再起動
  restart )
    killall Docker && open /Applications/Docker.app
    printf $TEXT_SUCCESS "Docker will restart."
    ;;
  ### [doc ls] Dockerの動作状況を確認
  ls|list|'' )
    local -r color_reset="\x1b[0m"
    docker ps -a --format "table 　{{.Names}} ({{.ID}})\t{{.Status}}\t{{.Size}}" \
     | sed -r "s/^　(.* Created .*)$/🌱${COLOR_SUCCESS}\1${COLOR_RESET}/g" \
     | sed -r "s/^　(.* Up .*)$/🌳\1/g" \
     | sed -r "s/^　(.* Exited .*)$/　${COLOR_MUTED}\1${COLOR_RESET}/g"
    ;;
  ### [doc clean] 起動中のコンテナをすべて停止する
  clean|sweep )
    local container_ids=$(docker ps -q)
    if [ -n "$container_ids" ]; then
      local count=$(docker stop $(docker ps -q) | wc -l | sed -e 's/ //g')
      printf $TEXT_SUCCESS "${count} containers stopped!"
    else
      printf $TEXT_WARNING "No containers running."
    fi
    ;;
  ### [doc bash] 起動中のコンテナに接続する
  bash )
    [ ${args[2]} ] && local container=${args[2]} || local container='web'
    printf $TEXT_INFO_DARK "Start connecting on ${container}..."
    docker compose exec -it ${container} bash
    ;;
  esac
;;

## [edit] スクリプトと設定の編集
edit )
  code -n $SCRIPT_DIR

  ## --init スクリプトの初期設定
  if [ -n "$args[init]" ]; then
    code --diff ${SCRIPT_DIR}/sample/zshrc_sample ~/.zshrc
    code --diff ${SCRIPT_DIR}/sample/gitconfig_sample $(git config --global --list --show-origin --name-only | head -1 | sed 's/file:\(.*\)\t.*/\1/')
  fi
;;

## [refresh] スクリプトと設定の変更を反映
refresh )
  source ${TOOL_SCRIPT}
  printf $TEXT_SUCCESS "Tool script is refreshed."
;;

## [git] Gitクライアントを開く
git )
  local remote_params=$(git remote -v | sed -n -e 1p)
  if [[ $remote_params =~ '^origin.*https://' ]]; then
    local url=$(echo $remote_params | grep -oe "https://.*\.git" | sed "s|\.git|/${query}|")
  else
    local url="https://github.com/$(echo $remote_params | grep -oe "[a-zA-Z-]*/.*\.git" | sed "s|\.git|/${query}|")"
  fi

  case $args[1] in
  ### [git] リポジトリの状況をアプリケーションで表示
  ''|tree|t )
    printf $TEXT_INFO 'Start openning repository on git client…'
    open -a $APP_GIT_CLIENT $PROJECT_DIR
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
      git branch --set-upstream-to=origin/${branch_name} ${branch_name} &> /dev/null
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

    printf $TEXT_DANGER "Would you like to overwrite ${branch_name}? (y/n)"
    read answer

    if [ "$answer" = "y" ]; then
      git fetch origin
      git reset --hard "origin/${branch_name}"
    fi
    ;;
  ### [git clean] マージされたブランチlogを一括削除
  ### --all ベースブランチを除外したすべてのブランチを対象とする
  clean )
    if [[ -n "${options[all]}" ]]; then
      local branches=$(git branch --merged | egrep -v "main|master|develop|staging|stg|dev|\* ")
    else
      local branches=$(git branch --merged | egrep -v "main|master|\* " | egrep "${BRANCH_PREFIX}|issue|fix|feature")
    fi
    if [ -n "$branches" ]; then
      printf "${branches}\n"
      printf $TEXT_WARNING "Would you like to remove merged branches? (y/n)"
      read answer
      if [ "$answer" = "y" ]; then
        echo ${branches} | xargs git branch -d
        git fetch --prune
        printf $TEXT_SUCCESS "Merged branches removed!"
      fi
    else
      printf $TEXT_WARNING "No merged branch."
    fi
    ;;
  ### [git amend] 現在ステージ中のファイルを前のコミットに追加コミットする
  amend )
    local commit_message=$(git log --oneline | head -n 1 | sed "s|^[a-z0-9]* ||")
    printf $TEXT_WARNING $commit_message
    git status --porcelain | grep -v "^ "
    printf $TEXT_DANGER "Would you like to override previous commit? (y/n)"
    read answer
    if [ "$answer" = "y" ]; then
      git commit --amend -m $commit_message
    fi
  ;;
  ### [git stash] 現在の変更点を一時退避する
  stash )
    git stash --include-untracked
  ;;
  newpr )
    local branch_name=$(git rev-parse --abbrev-ref HEAD)
    local branch_name="Y_CENTER-771"
    open "${url}/compare/${branch_name}?expand=1"
    sleep 1


    # browser_selector_input '[name="pull_request[title]"]' "タイトル"
    # sleep 1
    browser_selector_input '[name="pull_request[body]"]' "ファンクション2"
  ;;
  * )
    open -a $BROWSER ${url}
  esac
;;

## [<number>] 番号から規定のブランチをチェックアウトする
[0-9]* )
  local branch="${BRANCH_PREFIX}${action}"
  if [ -n "$(git branch --format="%(refname:short)" | grep ^${branch}$)" ]; then
    git checkout ${branch}
  else
    printf $TEXT_WARNING "Branch '${branch}' not found."
  fi
;;

## [-] 前のブランチをチェックアウトする
- )
  echo $action
  git checkout ${action}
;;

## [rename] ディレクトリ内のファイル名一括変更
rename )
  local files=($(ls -1F | grep -v / | xargs))

  printf $TEXT_INFO $files
  printf $TEXT_WARNING "ファイル名を入力してください..."

  declare -A new_names

  for file in ${files}; do
    printf $TEXT_INFO_DARK "${file} >>"
    read new_name
    new_names[$file]=$new_name
  done

  for old_name in "${(ko)new_names[@]}"; do
    local new_name=$new_names[$old_name];
    [ "$old_name" = "$new_name" ] && local text_color=$TEXT_MUTED || local text_color=$TEXT_SUCCESS
    printf $text_color "${old_name} >> ${new_name}"
  done

  printf $TEXT_WARNING "Would you like to rename? (y/n)"
  read answer
  case $answer in
  y)
    for old_name in "${(ko)new_names[@]}"; do
      mv -f $old_name $new_names[${old_name}]
    done
    printf $TEXT_SUCCESS "Renamed!"
    ;;
  *) ;;
  esac
;;

# [mkdir] ディレクトリを作成して移動
mkdir )
  local dir=$args[1]
  if [[ -d $dir ]]; then
    echo "${dir} already exists!"
    cd $dir
  else
    mkdir -p $dir
    cd $dir &> /dev/null
    ls -l ..
  fi
;;

## [open <environment>] Webサイトのホームを開く
## --alt 規定でないブラウザで開く
open )
  [ -n "${options[alt]}" ] && browser_options=(--alt) || browser_options=()
  open_in_browser "$(project_origin $args[1])${URL_FRONT}" ${browser_options}
;;

## [admin <environment>] Webサイトの管理画面を開く
## --alt 規定でないブラウザで開く
admin )
  [ -n "${options[alt]}" ] && browser_options=(--alt) || browser_options=()
  open_in_browser "$(project_origin $args[1])${URL_ADMIN}" ${browser_options}
;;

## [diff] ベースブランチからの差分を確認
## --copy 出力内容をクリップボードにコピーする
diff )
  case $args[1] in
  ### [diff main] メインブランチの最新コミットの差分を確認
  master|main )
    local target="$args[1]..$args[1]~1"
    ;;
  ### [diff copy] 出力内容をクリップボードにコピーする
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
    printf $TEXT_DANGER "差分ファイルがありません"
    return
  fi

  printf $TEXT_INFO "$(echo $file_changes | grep -c '') files changed. (${target})"
  printf "${file_changes}\n"

  if [[ -n "${options[copy]}" ]]; then
    echo ${file_changes} | pbcopy
    printf $TEXT_SUCCESS "差分ファイルリストをクリップボードにコピーしました"
  fi
;;

## [dist] 差分ファイルをdist出力する
## --commit 直前のコミットのみを対象とする
## --all ファイルを除外しない
## --copy 実行せずコピーする
dist )
  local base_commit=$(git merge-base ${BASE_BRANCH} HEAD)

  case $args[1] in
  ### [dist ls] ファイル確認
  ls )
    printf $TEXT_WARNING "distフォルダを表示します"
    tree -a "${DEST_DIR}"
    ;;
  ### [dist rm] ファイル削除
  rm)
    rm -rf ${DEST_DIR} &> /dev/null
    mkdir ${DEST_DIR} &> /dev/null
    printf $TEXT_WARNING "distフォルダを削除しました"
    ;;
  * )
    rm -rf ${DEST_DIR} &> /dev/null
    mkdir ${DEST_DIR}
    cd "${WORKSPACE}/${PROJECT_NAME}/" &> /dev/null

    ### [dist copy] 実行せずコマンドをコピーする
    if [ "$args[1]" = "copy" ]; then
      options[copy]="1"
    fi

    # 対象コミット範囲
    if [[ -n "${options[commit]}" ]]; then
      local files=$(git diff --name-only --diff-filter=MAR HEAD^..HEAD)
      local target_name="直前のコミットの変更"
    else
      local files=$(git diff --name-only --diff-filter=MAR ${base_commit}..HEAD)
      local target_name="${BASE_BRANCH}ブランチからの差分"
    fi

    # 除外ファイル
    if [[ -n "${options[all]}" ]]; then
      target_name+="全ファイル"
    else
      # デフォルトで設定ファイルを除外する
      files=$(echo $files | grep -vE ^app/config)
    fi

    if [[ -n "${options[copy]}" ]]; then
      echo $files | xargs -I {} echo "rsync -R {} ${DEST_DIR}" | pbcopy
      printf $TEXT_SUCCESS "${target_name}の出力コマンドをクリップボードにコピーしました"
    else
      echo $files | xargs -I {} rsync -R {} ${DEST_DIR}
      printf $TEXT_WARNING "${target_name}をdistフォルダにコピーしました"
    fi

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
      [ -v $DEPLOY_TO ] && printf $TEXT_DANGER "Deploy path is not configured. (${env})" && return
      ;;
  esac

  tree $DEST_DIR

  if check_config_exists; then
    printf $TEXT_WARNING "設定ファイルが含まれています！"
  else
    [ "$env" = "production" ] && printf $TEXT_DANGER "- DEPLOY TO PRODUCTION !!"
    if [ "$2" = "-y" ]; then
      local answer="y"
    else
      printf $TEXT_WARNING "Would you like to deploy under dist to ${env}? (y/n)"
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

      printf $TEXT_SUCCESS "Deployed!"
      ;;
    *) ;;
  esac
;;

## [build] リリースファイルを作成する (未メンテナンス)
build )
  rm -rf ${DEST_DIR} &> /dev/null
  mkdir ${DEST_DIR}
  local base_commit="master"
  local release_commit="$BASE_BRANCH"

  case $2 in
  ## --copy 実行せずコマンドをコピーする
  --copy )
    git diff --name-only --diff-filter=MAR ${base_commit}..${release_commit} | xargs -I {} echo "rsync -R {}  ${DEST_DIR}" | pbcopy
    printf $TEXT_WARNING "${BASE_BRANCH}ブランチからの差分ファイル出力用rsyncコマンドをコピーしました"
    ;;
  *)
    git diff --name-only --diff-filter=MAR ${base_commit}..${release_commit} | grep -vE ^app/config | xargs -I {} rsync -R {}  ${DEST_DIR}
    zip -r "${DEST_DIR}/${BACKLOG_PREFIX}.zip" "${DEST_DIR}/${DEPLOY_DIR}"
    printf $TEXT_WARNING "${BASE_BRANCH}ブランチからの差分ファイルをdistフォルダにコピーしました"
    ;;
  esac
;;

selenium )
  if type chromedriver > /dev/null 2>&1; then
    curl -X POST -H 'Content-Type: application/json' \
      -d '{"desiredCapabilities": { "browserName": "chrome" }}' \
      http://localhost:9515/session
  else
    printf $TEXT_WARNING "Chromedriver is not installed. "
    printf $TEXT_WARNING "  Please run \`brew install chromedriver jq\` and permit it in system preferences"
    return
  fi
;;

## [ssh | ssh <environment>] SSH接続してアプリケーションルートに移動する
ssh )
  case $args[1] in
  ### [ssh staging] 接続先を指定する
  staging|s )
    #[ -v SSH_NAME_STAGING ] && printf $TEXT_DANGER "SSH name is not configured. (${env})" && return
    printf $TEXT_SUCCESS "Connecting to ${PROJECT_NAME} [staging]... (${APP_ROOT})"
    ssh ${SSH_NAME_STAGING} -t "cd ${APP_ROOT}; bash --login"
    ;;
  * )
    printf $TEXT_SUCCESS "Connecting to ${PROJECT_NAME} [local]... (${APP_ROOT})"
    cd_vagrant
    vagrant ssh -c 'cd "/var/www/$(ls /var/www | more)"; bash --login'
    ;;
  esac
;;

## [sshkey <ssh_name>]
sshkey )
  if [ -z "${args[1]}" ]; then
    printf $TEXT_WARNING "引数1にSSH接続名を指定してください。"
    return
  fi

  printf $TEXT_SUCCESS "${args[1]}に追加する公開鍵を入力してください。"
  echo -n "public_key: "
  read public_key
  if [ -z "${public_key}" ]; then
    echo "公開鍵設定を中止しました。"
    return
  fi
  ssh ${args[1]} "mkdir -p ~/.ssh; echo "${public_key}" >> ~/.ssh/authorized_keys"
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
  ### [vangrant command] Vagrantでコマンドを入力する
  c|command )
    if [ $# ]; then
      vagrant ssh -c "$*"
    else
      print "コマンドが入力されていません"
    fi
    ;;
  ### [vagrant status] すべてのVagrantの動作ステータスを表示する
  status )
    vagrant global-status
    ;;
  ### [vagrant clean] すべてのVagrantを停止する
  clean|sweep )
    vagrant global-status | grep 'virtualbox running' | sed 's|^\([^ ]*\).*|\1|' | xargs -I {} vagrant suspend {}
    ;;
  ### [vagrant up] 他の仮想マシンを停止してVagrantを起動する
  up )
    vagrant global-status | grep 'virtualbox running' | sed 's|^\([^ ]*\).*|\1|' | xargs -I {} vagrant suspend {}
    vagrant up
    ;;
  ### [vagrant *] Vagrantコマンドを実行する
  * )
    vagrant ${args}
  esac

  cd -
;;

## [db] 仮想マシンのSQLに接続する
db )
  if [[ "$VM_PLATFORM" == "vagrant" ]]; then
    cd_vagrant
    vagrant ssh -c "psql ${@:2}"
  else
    eval "local -A docker_env=($(docker_container_env))"
    eval "docker compose exec -it db psql -U ${docker_env[POSTGRES_USER]} -d ${docker_env[POSTGRES_DB]}"
  fi
;;

## [aws] プロジェクト名をプロファイル名としてAWS CLIを使用する
aws )
  aws --profile ${PROJECT_NAME} ${@:2}
;;

## [log <environment>] ログファイルを表示する
log )
  case $(parse_environment $args[1]) in
  production ) local domain="${DOMAIN_PRODUCTION}" ;;
  staging )
    ssh -t ${SSH_NAME_STAGING} "tail -f ${LOG_PRODUCTION}" | ccze -A
    ;;
  local )
    [ $# = 2 ] && local filepath="$2" || local filepath="${LOG_LOCAL}"
    watch_vm_file "${filepath}"
  esac
;;

## [bl] Backlogをブラウザで開く
bl )
  [ -v $BACKLOG_PREFIX ] && printf $TEXT_DANGER "Backlog prefix is not configured." && return
  local store_ini="${SCRIPT_DIR}/config/store.ini"
  local store_key_prefix="${PROJECT_NAME}_"

  case $args[1] in
  ### [bl <number>] 現在ブランチ名に応じて課題を開く
  [0-9]* )
    open "https://hotfactory.backlog.jp/view/${BACKLOG_PREFIX}-$2"
    ;;
  ### [bl ls] Backlog課題一覧を開く
  ls )
    open "https://hotfactory.backlog.jp/find/${BACKLOG_PREFIX}"
    ;;
  ### [bl wiki] BacklogのWikiホームを開く
  wiki )
    open "https://hotfactory.backlog.jp/wiki/${BACKLOG_PREFIX}/Home"
    ;;
  ### [bl set <project_id>] Backlog課題番号とブランチ名の対応リストを追加する
  set )
    if expr "${args[2]}" : "[0-9]*" &> /dev/null; then
      local branch_name=$(git rev-parse --abbrev-ref HEAD)
      local backlog_task_id="${BACKLOG_PREFIX}-${args[2]}"

      set_ini "${store_key_prefix}${branch_name} = ${backlog_task_id}" ${store_ini} --section=backlog_task_id
      echo "Backlog課題番号を登録しました。[${branch_name} → ${backlog_task_id}]"
    else
      echo "Backlog課題番号を指定してください"
    fi
    ;;
  * )
    local branch_name=$(git rev-parse --abbrev-ref HEAD)
    local stored_task_id=$(parse_ini ${SCRIPT_DIR}/config/store.ini --section=backlog_task_id --key=${store_key_prefix}${branch_name})

    if [ -n "$stored_task_id" ]; then
      # iniに設定されたブランチがあれば課題を開く
      printf $TEXT_INFO_DARK "Found a backlog task relation. [${branch_name} → ${stored_task_id}]"
      open "https://hotfactory.backlog.jp/view/${stored_task_id}"
    elif [[ $branch_name == "${BACKLOG_PREFIX}-"* ]]; then
      # Backlog課題形式のブランチ名であれば課題を開く
      open "https://hotfactory.backlog.jp/view/${branch_name}"
    else
      # 一致しなければ課題一覧を開く
      printf $TEXT_INFO_DARK "Open backlog project"
      open "https://hotfactory.backlog.jp/find/${BACKLOG_PREFIX}"
    fi
    ;;
  esac
;;

## [master | main | staging | stg | develop | dev] ベースブランチのチェックアウト
master|main|staging|stg|develop|dev|$BASE_BRANCH )
  local branch="${action}"
  if [ -n "$(git branch --format="%(refname:short)" | grep ^${branch}$)" ]; then
    git checkout ${branch}
    git pull
  else
    printf $TEXT_WARNING "Branch '${branch}' not found."
  fi
;;

## [new <branch_name>] 新しいブランチを作成してチェックアウトする
new )
  if expr "$2" : "[0-9]*" &> /dev/null; then
    local branch_name="${BRANCH_PREFIX}$2"
  else
    local branch_name="$2"
  fi
  git checkout -b ${branch_name} &> /dev/null
  echo "ブランチ『${branch_name}』を作成しました"
;;

## [forcepull] リモートブランチでローカルブランチを上書きする
forcepull )
  local branch_name=$(git rev-parse --abbrev-ref HEAD)
  local base_commit=$(git merge-base ${BASE_BRANCH} HEAD)
  git log --oneline --graph $base_commit..HEAD

  printf $TEXT_DANGER "Would you like to overwrite ${branch_name}? (y/n)"
  read answer

  if [ "$answer" = "y" ]; then
    git fetch origin
    git reset --hard "origin/${branch_name}"
  fi
;;

## [pmlog] システムのスリープ履歴を表示
pmlog )
  ## -a ディスプレイの電源切り替えも表示する
  if [[ -n "${options[a]}" ]]; then
    printf $TEXT_INFO 'Process manager log: sleep, display'
    pmset -g log | grep -e 'Charge' -e 'Display is turned' -e 'Entering Sleep' -e 'Wake from'
  else
    printf $TEXT_INFO 'Process manager log: sleep'
    pmset -g log | grep -e 'Entering Sleep' -e 'Wake from'
  fi
;;

## [..] プロジェクトルートに移動
.. )
  cd ${PROJECT_DIR}
;;

## [ws <directory>] プロジェクトルートに移動する 引数分ディレクトリを深掘りして曖昧検索する
ws )
  if [ -z "${args}" ]; then
    cd $WORKSPACE &> /dev/null
    ls
  else
    local project_path=$WORKSPACE
    local project_name=""

    for arg in ${args}; do
      # 前方一致
      local prefix_regex="^${arg}.*"
      # 前方スネークケース
      local snake_regex="^$(echo ${arg} | sed 's|.|&_*|g')"
      # あいまい検索
      local fuzzy_regex="^$(echo ${arg} | sed 's|.|&.*|g')"

      # まず前方一致で確認、一致がない場合はあいまい検索で検索で再検索
      local target_dir=$(ls $project_path | grep -s -m1 $prefix_regex)
      if [ -z $target_dir ]; then
        target_dir=$(ls $project_path | grep -s -m1 $snake_regex)
      fi
      if [ -z $target_dir ]; then
        target_dir=$(ls $project_path | grep -s -m1 $fuzzy_regex)
      fi
      project_name=$target_dir
      project_path+="/${target_dir}"
    done

    printf $TEXT_INFO "Project: ${project_name}"
    cd ${project_path} &> /dev/null
  fi
;;

## [telescope] Laravel Telescopeをブラウザで開く
telescope )
  local browser_options=()
  [ -n "${options[alt]}" ] && browser_options+="--alt"
  open_in_browser "$(project_origin)/telescope/queries" ${browser_options}
;;

## [help] ヘルプメッセージを表示
help | '' )
  print_help
;;

## [<etc>] アクション名が一致しなかった場合は追加のアクションを読み込み
* )
  local addition_path="${SCRIPT_DIR}/config/addon.sh"
  [ -f "${addition_path}" ] && source ${addition_path}
esac # Actions

# 最後に関数をすべて削除
unset_functions
}
