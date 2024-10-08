# toコマンドの定義
# 処理はサブシェルで実行
# @exit 0 成功
# @exit 1 失敗
# @exit 2 オプションや値が不正
# @exit $EXIT_CODE_WITH_ADDITION メインシェルで追加処理を実行
# @exit 27 アクションが見つからない
to() {
# 定数の読み込み
source ~/.zsh/src/constants.sh

(
# サブシェル内で関数の終了ステータスが0以外の場合はスクリプトを中断
# サブシェル自体の戻り値は影響しない
set -e

# 関数の読み込み
source $FUNCTIONS_PATH

# 引数とオプションを取得 ${args[1]}: 引数1 ${args[some_key]}: オプション(指定なしで値は1)
# $optionsは順次$argsに統一していく
local action=$1
local -A args=($(parse_arguments ${@:2}))
local -A options=(${(kv)args})

# --help オプションが指定された場合はヘルプメッセージを表示して完了
if [[ -n "${options[help]}" ]]; then
  print_help $action
  return
fi

# プロジェクト定数
local -r PROJECT_DIR=$(get_project_root)
local -r PROJECT_NAME=$(basename ${PROJECT_DIR})
source <(parse_ini ${SCRIPT_DIR}/config/projects.ini --section=default | sed "s/^ */local /g")
source <(parse_ini ${SCRIPT_DIR}/config/projects.ini --section=${PROJECT_NAME} | sed "s/^ */local /g")

# アクションを実行する
case $action in

## [help] ヘルプメッセージを表示
help | '' )
  print_help
;;

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

  ## --color 文字装飾見本を追加表示する
  if [ -n "${args[color]}" ]; then
    printf $TEXT_INFO "Colors:"

    echo "  ${COLOR_SUCCESS}COLOR_SUCCESS${COLOR_RESET}"
    echo "  ${COLOR_DANGER}COLOR_DANGER${COLOR_RESET}"
    echo "  ${COLOR_WARNING}COLOR_WARNING${COLOR_RESET}"
    echo "  ${COLOR_NOTICE}COLOR_NOTICE${COLOR_RESET}"
    echo "  ${COLOR_INFO}COLOR_INFO${COLOR_RESET}"
    echo "  ${COLOR_INFO_DARK}COLOR_INFO_DARK${COLOR_RESET}"
    echo "  ${COLOR_MUTED}COLOR_MUTED${COLOR_RESET}"

    for i in {0..49}; do
      if [[ $(($i % 10)) == 0 ]]; then
        echo -n "\n  "
      fi

      local code=$((i++))
      echo -n "\x1b[${code}m${code}${COLOR_RESET} ";
    done
    echo "\n"
  fi

  emoji_pattern="[\x{1F600}-\x{1F64F}]"
  echo "$args[1]"

  local string="$args[1]"
  for (( i=0; i<${#string}; i++ )); do
    printf "\\x%02x" "'${string:$i:1}"
  done
;;

# [init] プロジェクトの初期設定
init )
  # WIP
  echo "${COLOR_INFO_DARK}project name:${COLOR_RESET} ${PROJECT_NAME}"

  local default

  # BASE_BRANCH
  default=$(parse_ini ${SCRIPT_DIR}/config/projects.ini --section=${BASE_BRANCH} --key=BASE_BRANCH)
  [ -z "$default" ] && default=$(git branch -r | grep HEAD | cut -d'/' -f3)
  echo -n "${COLOR_INFO_DARK}base branch (${default}):${COLOR_RESET} "
  read_with_default ${default} && local base_branch=${FUNCTION_REPLY}

  # PROJECT_NAME
  default=$(parse_ini ${SCRIPT_DIR}/config/projects.ini --section=${PROJECT_NAME} --key=DEPLOY_TYPE)
  [ -z "$default" ] && default=none
  echo "${COLOR_INFO_DARK}deploy type (${default}):${COLOR_RESET}"
  read_selection_long "none: なし" "dist: distフォルダ経由でファイルリリース" "deployer: リモートサーバーのでDeployer" && local DEPLOY_TYPE=${FUNCTION_REPLY}
  [[ "${DEPLOY_TYPE}" == "none" ]] && DEPLOY_TYPE=""
;;

## [ws <name>] ワークスペースディレクトリ内を曖昧検索してパスを出力する 引数分ディレクトリを深掘りする
ws )
  fuzzy_dir_search ${WORKSPACE} ${@:2}
;;

## [cp <from> <to>] Git除外ファイルを考慮してコピー
cp )
  rsync -rcv $args[1] $args[2] --exclude='.DS_Store' --exclude='/.git' -C --filter=":- .gitignore"
;;

## [rm] ファイルやディレクトリをゴミ箱に入れる
rm )
  local trash_dir="${HOME}/.Trash"

  if [ -n "${args[revert]}" ]; then
    ## --revert 削除したファイルをカレントディレクトリに戻す (ファイル名重複未対応)
    for arg_key in ${(k)args[@]}; do
      if [[ "$arg_key" =~ ^[0-9]+$ ]]; then
        local arg=$args[$arg_key]
        # ゴミ箱の中に重複するファイル名がある場合は時間を付加する
        if [ -e "${arg}" ]; then
          printf $TEXT_DANGER "File already exists. (${arg})"
          return
        fi

        local target="${trash_dir}/$(basename ${arg})"
        if [ -d "${target}" ]; then
          mv ${target} ${arg}
          printf $TEXT_SUCCESS "Successfly revert directory. (~/.Trash/$(basename ${arg}) > ${arg})"
          ll -d ${arg}
        elif [ -f "${target}" ]; then
          mv ${target} ${arg}
          printf $TEXT_SUCCESS "Successfly revert file. (~/.Trash/$(basename ${arg}) > ${arg})"
          ll ${arg}
        else
          printf $TEXT_DANGER "File or directory not exists. (${target})"
        fi
      fi
    done
  else
    for arg in ${args[@]}; do
      # ゴミ箱の中に重複するファイル名がある場合は時間を付加する
      local filename=$(basename ${arg})
      [ -e "${trash_dir}/${filename}" ] && local needsRename=true || local needsRename=false
      $needsRename && local trashname="${filename} $(date +%y.%m.%d)" || local trashname="${filename}"
      $needsRename && local result="${filename} > ~/.Trash/${trashname}" || local result="${filename}"

      if [ -d "${arg}" ]; then
        mv ${arg} "${trash_dir}/${trashname}"
        printf $TEXT_SUCCESS "Successfly removed directory. (${result})"
      elif [ -f "${arg}" ]; then
        mv ${arg} "${trash_dir}/${trashname}"
        printf $TEXT_SUCCESS "Successfly removed file. (${result})"
      else
        printf $TEXT_DANGER "File or directory not exists. (${arg})"
      fi
    done
  fi
;;

## [..] プロジェクトルートに移動
.. )
  ## --path パスを出力する
  if [ -n "${args[path]}" ]; then
    echo $PROJECT_DIR;
    return
  fi
  # ディレクトリ移動はサブシェル外で実行する
  exit $EXIT_CODE_WITH_ADDITION &> /dev/null
;;

## [edit] スクリプトと設定の編集
edit )
  code -n $SCRIPT_DIR

  ## --init スクリプトの初期設定
  if [ -n "$args[init]" ]; then
    code --diff ${SCRIPT_DIR}/sample/zshrc.sample ~/.zshrc
    echo "SCRIPT: ${SCRIPT_DIR}"

    local filepaths=($(find ${SCRIPT_DIR}/sample/config -type f))
    for filepath in "${filepaths[@]}"; do
      local target_path="${SCRIPT_DIR}/config/$(basename ${filepath} | sed 's/\.sample$//')"
      if [ -e "${target_path}" ]; then
        printf $TEXT_MUTED "${target_path} (already exists)"
      else
        printf $TEXT_SUCCESS "${target_path} << ${filepath}"
        cp ${filepath} ${target_path}
      fi
    done
  fi
;;

## [refresh] スクリプトと設定の変更を反映
refresh )
  if [ -n "${args[path]}" ]; then
    ## --path パスを出力する
    echo ${TOOL_SCRIPT}
  else
    printf $TEXT_SUCCESS "Tool script is refreshing..."

    # 再読み込みはサブシェル外で実行する
    exit $EXIT_CODE_WITH_ADDITION &> /dev/null
  fi
;;

## [sync] スクリプトと設定ファイルの同期管理
sync )
  local sub_action=${args[1]}
  if [ -z "${sub_action}" ]; then
    printf $TEXT_INFO "Choose sub action."
    read_selection_long "ls: ファイル一覧" "diff: 差分一覧" "export: 同期保存" "import: 同期読み込み" && sub_action=${FUNCTION_REPLY}
  fi

  case ${sub_action} in
  ### [sync ls] 反映中スクリプトの確認
  ls )
    ls -lohpTSG $SCRIPT_DIR
    ;;
  ### [sync diff] エクスポートされている設定ファイルとの差分を表示
  diff )
    diff -r ${SCRIPT_DIR} ${EXPORT_DIR} | sed "s/^\(-\{1,3\} .*\)$/${COLOR_DANGER}\1${COLOR_RESET}/" | sed "s/^\(+\{1,3\} .*\)$/${COLOR_SUCCESS}\1${COLOR_RESET}/"
    ;;
  ### [sync export] スクリプトと設定ファイルをエクスポートする
  export )
    printf $TEXT_WARNING "シェルスクリプトの設定ファイルをエクスポートしますか？"
    printf $TEXT_WARNING "${SCRIPT_DIR} > ${EXPORT_DIR}"
    read_confirmation

    rsync -rcv "${SCRIPT_DIR}/" $EXPORT_DIR --exclude='.DS_Store' --exclude='/.git' -C --filter=":- .gitignore"
    printf $TEXT_SUCCESS "シェルスクリプトを保存しました"
    ;;
  ### [sync import] スクリプトと設定ファイルをインポートする
  import )
    printf $TEXT_WARNING "シェルスクリプトの設定ファイルを上書きインポートしますか？"
    printf $TEXT_WARNING "${EXPORT_DIR} > ${SCRIPT_DIR}"
    read_confirmation

    rsync -rcv "${EXPORT_DIR}/" $SCRIPT_DIR --exclude='.DS_Store' --exclude='/.git' -C --filter=":- .gitignore"
    printf $TEXT_SUCCESS "シェルスクリプトを読み込みました"
  ;;
  * )
    exit $EXIT_CODE_WRONG_ARGUMENT &> /dev/null
  esac
;;

## [timer] 経過時間計測を開始する
timer )
  ## --clean タイマーを全削除する
  if [ -n "$args[clean]" ]; then
    local process_count=$(ps | grep "sleep [0-9]\+.00000" | wc -l | sed -e 's/ //g')

    if [[ ${process_count} == 0 ]]; then
      printf $TEXT_WARNING "No timer running."
      exit $EXIT_CODE_ERROR &> /dev/null
    fi

    ps | grep "sleep [0-9]\+.00000" | awk '{print $1}' | xargs kill -9
    printf $TEXT_SUCCESS "${process_count} timer(s) removed."
    return
  fi

  if [ -z "$args[1]" ]; then
    local start=$(date +%s)

    printf $TEXT_INFO "Press Control + C to stop the timer."
    while true; do
      local end=$(date +%s)
      local timestamp=$((${end} - ${start}))
      local minutes=$((${timestamp} / 60))
      local seconds=$((${timestamp} % 60))
      printf "\rTimer: %3s:%02d secs" ${minutes} ${seconds}
      [ $minutes -ge 1000 ] && break
      sleep 1
    done
  fi

  if [[ ${args[1]} == *:* ]]; then
    ### [timer <MM:SS> <message>] 指定時刻のタイマーをセットする
    local target=$(date -jf "%H:%M:%S" "${args[1]}:00" +%s)
    local now=$(date +%s)
    local seconds=$((${target} - ${now}))

    # 過ぎた時刻なら翌日のタイムスタンプに変更
    if [ ${seconds} -lt 0 ]; then
      local seconds=$((${seconds} + 86400))
    fi

    [ -n "${args[2]}" ] && local message=${args[2]} || local message="Notice from tool script. ($(date -jf "%s" ${target} +%H:%M))"
  else
    ### [timer <duration><unit> <message>] 一定時間のタイマーをセットする
    local quantity=$(echo ${args[1]} | sed 's/^\([0-9]*\).*$/\1/')
    case $(echo ${args[1]} | sed 's/^[0-9]*//') in
    h|hour|hours )
      [[ ${seconds} > 1 ]] && local unit="hours" || local unit="hour"
      local seconds=$((${quantity} * 60))
      ;;
    m|min|minute|minutes )
      [[ ${seconds} > 1 ]] && local unit="minutes" || local unit="minute"
      local seconds=$((${quantity} * 60))
      ;;
    s|sec|second|seconds|'' )
      [[ ${seconds} > 1 ]] && local unit="seconds" || local unit="second"
      local seconds=${quantity}
      ;;
    * )
      exit $EXIT_CODE_WRONG_ARGUMENT &> /dev/null
    esac

    [ -n "${args[2]}" ] && local message=${args[2]} || local message="${quantity} ${unit} from $(date +%H:%M)"
  fi

  if [ ${seconds} -gt 10800 ]; then
    printf $TEXT_DANGER "The timer for no more than 3 hours."
    exit $EXIT_CODE_WRONG_ARGUMENT &> /dev/null
  fi

  # タイマーを登録 (削除時のプロセス判別のため小数点5位までゼロを指定しておく)
  (
    sleep "${seconds}.00000"
    osascript -e "display notification \"${message}\" with title \"Tool Script\""
  ) &
  printf $TEXT_SUCCESS "The timer has been set. (${message})"
;;

## [note] メモファイルの表示
note )
  local note_file="${SCRIPT_DIR}/config/note.txt"
  case $args[1] in
  ### [note edit] メモファイルを編集
  edit )
    vi ${note_file}
    ;;
  * )
    print_heading "Script Note"

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
  ### [doc bash <container>] Dockerコンテナに接続 (コンテナ未指定で選択)
  bash )
    local container=${args[2]}
    if [ ! ${container} ]; then
      printf $TEXT_INFO "Choose docker container to connect."
      read_selection $(docker compose config --services | tail -r) && local container=${FUNCTION_REPLY}
    fi

    # 設定ファイルの組み込み
    local bash_profile_path="/root/.bash_profile"
    local docker_profile_path="/root/.docker_profile"
    local text="source ${docker_profile_path}"
    if docker compose exec ${container} grep -q ${text} ${bash_profile_path}; then; else
      printf $TEXT_INFO "Setting to ${container} bash profile."
      docker compose exec ${container} /bin/sh -c "echo ${text} >> ${bash_profile_path}"
      docker compose cp ${SCRIPT_DIR}/src/docker_profile.sh ${container}:${docker_profile_path}
    fi
う
    # コンテナへの接続
    printf $TEXT_INFO "Start connecting on ${container}... (docker compose exec -it ${container} bash --login)"
    docker compose exec -it -e PS1="\[\e[1;32m\][docker:${container}] \[\e[0;32m\]\W\[\e[m\] " ${container} bash --login
    ;;
  ### [doc destroy] カレントディレクトリのコンテナをイメージやボリュームを含めて削除する
  destroy )
    printf $TEXT_WARNING "Would you like to delete docker containers?"
    read_confirmation

    docker compose down --rmi all --volumes --remove-orphans
    ;;
  esac
;;

## [bash <contaner>] Dockerコンテナに接続 (コンテナ未指定で最初のコンテナ)
bash )
  local container=${args[2]}
  if [ ! ${container} ]; then
    container=$(docker compose config --services | tail -r | head -1)
    printf $TEXT_INFO "Default container: ${container}"
  fi
  to doc bash ${container} ${@:3}
;;

## [git] Gitクライアントを開く
git )
  case $args[1] in
  ''|tree|t )
    # リポジトリの確認
    local repositry_dir
    repositry_dir=$(git rev-parse --show-toplevel)
    printf $TEXT_INFO "Start openning $(basename ${repositry_dir}) repository on git client…"
    open -a $APP_GIT_CLIENT $PROJECT_DIR
    ;;
  ### [git init] Git設定ファイルを編集する
  init )
    code -n $SCRIPT_DIR
    code --diff ${SCRIPT_DIR}/sample/gitconfig.sample $(git config --global --list --show-origin --name-only | head -1 | sed 's/file:\(.*\)\t.*/\1/')
    ;;
  ### [git checkout] WIP ブランチをチェックアウトする
  checkout|co )
    printf $TEXT_INFO "Choose a branch."
    read_git_branch && local branch=${FUNCTION_REPLY}
    git checkout ${branch}
    ;;
  ### [git code] GitHubのCodeページを開く
  code )
    open -a $BROWSER $(github_url)
    ;;
  ### [git i] GitHubのIssuesページを開く
  issue|is|i )
    open -a $BROWSER "$(github_url)/issues"
    ;;
  ### [git p] GitHubのPull Requestsページを開く
  pulls|pr|p )
    open_git_pulls ${@:3}
    ;;
  ### [git pull] チェックアウトせずにリモートブランチをプルする
  pull )
    ### --force | -f 現在のブランチを強制的にプルする
    if [ -n "$args[force]" ] || [ -n "$args[f]" ]; then
      [ -n "$args[2]" ] && exit $EXIT_CODE_WRONG_ARGUMENT &> /dev/null

      local branch_name=$(git rev-parse --abbrev-ref HEAD)
      local base_commit=$(git merge-base ${BASE_BRANCH} HEAD)
      git log --oneline --graph $base_commit..HEAD

      printf $TEXT_DANGER "Would you like to force overwrite '${branch_name}'?"
      read_confirmation

      git fetch origin
      git reset --hard "origin/${branch_name}"
      return
    fi

    case $args[2] in
    "" )
      # ブランチ指定なしで選択してプル
      printf $TEXT_INFO "Choose a branch to pull."
      read_git_branch && local branch=${FUNCTION_REPLY}
      ;;
    [0-9]* )
      # 数値のみ指定でデフォルトブランチ
      local branch="${BRANCH_PREFIX}${args[2]}"
      ;;
    * )
      local branch="${BRANCH_PREFIX}${args[2]}"
    esac
    git fetch origin ${branch}:${branch}
    ;;
  ### [git forcepush] ブランチを強制的にプッシュする
  forcepush )
    git push --force-with-lease --force-if-includes
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
      printf $TEXT_WARNING "Would you like to remove merged branches?"
      read_confirmation

      echo ${branches} | xargs git branch -d
      git fetch --prune
      printf $TEXT_SUCCESS "Merged branches removed!"
    else
      printf $TEXT_WARNING "No merged branch."
    fi
    ;;
  ### [git amend] 現在ステージ中のファイルを前のコミットに追加コミットする
  amend )
    ### --date コミット日付も変更する
    if [ -n "$options[date]" ]; then
      local original_date=$(git log --date=iso --date=format:"%Y-%m-%d" --pretty=format:"%ad" -1)
      local original_time=$(git log --date=iso --date=format:"%H:%M:%S" --pretty=format:"%ad" -1)

      echo -n "${COLOR_INFO}Date (${original_date}): ${COLOR_RESET}"
      local commit_date
      read commit_date
      [ -z "$commit_date" ] && commit_date=$original_date
      echo -n "${COLOR_INFO}Time (${original_time}): ${COLOR_RESET}"
      local commit_time
      read commit_time
      [ -z "$commit_time" ] && commit_time=$original_time
      local commit_date="${commit_date} ${commit_time}"
    fi

    local commit_message=$(git log --oneline | head -n 1 | sed "s|^[a-z0-9]* ||")
    printf $TEXT_WARNING $commit_message
    #git status --porcelain | grep -v "^ "
    git status --porcelain
    printf $TEXT_DANGER "Would you like to override previous commit?"
    read_confirmation

    if [ -n "$commit_date" ]; then
      git commit --amend -m $commit_message --date="$commit_date" --allow-empty

      local commit_total_count=$(git rev-list --count HEAD)
      if (( $(git rev-list --count HEAD) > 1 )); then
        git rebase HEAD~1 --committer-date-is-author-date
      else
        # ファーストコミットのみ
        git rebase --root --committer-date-is-author-date
      fi
    else
      git commit --amend -m $commit_message
    fi
  ;;
  ### [git stash] 現在の変更点を一時退避する (新規追加したファイルも含む)
  stash )
    git stash --include-untracked
  ;;
  ### [git newpr] 新規にプルリクエストを作成する
  newpr )
    local branch_name=$(git rev-parse --abbrev-ref HEAD)
    if [[ $branch_name == "${BACKLOG_PREFIX}-"* ]]; then
      # Backlog課題形式のブランチ名であれば課題名を取得
      local backlog_issue_key=$(echo $branch_name | sed "s/\(${BACKLOG_PREFIX}-[0-9]*\).*/\1/")
      open "https://hotfactory.backlog.jp/view/${backlog_issue_key}"
      sleep 2
      local task_name=$(browser_inner_text '#summary')
    fi

    open "$(github_url)/compare/${branch_name}?expand=1"
    sleep 2


    browser_input_value '[name="pull_request[title]"]' "${branch_name} ${task_name}"
    browser_input_value '[name="pull_request[body]"]' "## Backlog\nhttps://hotfactory.backlog.jp/view/${backlog_issue_key}\n\n## 対応内容\n"




    # sleep 4
    # browser_input_new "${branch_name} ${task_name}"
    # if [ -n "${task_name}" ]; then
    #   browser_input_new "## Backlog\nhttps://hotfactory.backlog.jp/view/${backlog_issue_key}\n\n## 対応内容\n" 1
    # else
    #   browser_input_new "## 対応内容\n" 1
    # fi
    ;;
  log )
    git log --graph --oneline --decorate
    ;;
  * )
    exit $EXIT_CODE_WRONG_ARGUMENT &> /dev/null
  esac
;;

## [master | main | staging | stg | develop | dev] ベースブランチのチェックアウト
master|main|staging|stg|develop|dev|$BASE_BRANCH )
  local branch="${action}"
  if [ -n "$(git branch --format="%(refname:short)" | grep ^${branch}$)" ]; then
    git checkout ${branch}
    git pull
  else
    local suggestion_branch=${BASE_BRANCH}
    [ "$branch" = "master" ] && suggestion_branch="main"
    [ "$branch" = "main" ] && suggestion_branch="master"
    printf $TEXT_WARNING "Branch '${branch}' not found. Did you mean '${suggestion_branch}'?"
  fi
;;

## [<number>] 番号から規定のブランチをチェックアウトする
[0-9]* )
  local branch="${BRANCH_PREFIX}${action}"
  if [ -n "$(git branch --format="%(refname:short)" | grep ^${branch}$)" ] || [ -n "$(git branch -r --format="%(refname:short)" | grep ^origin/${branch}$)" ]; then
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

## [rename] ディレクトリ内のファイル名一括変更
rename )
  local files=($(ls -1F | grep -v / | xargs))

  printf $TEXT_INFO $files
  printf $TEXT_WARNING "ファイル名を入力してください..."

  declare -A new_names

  for file in ${files}; do
    printf $TEXT_INFO "${file} >>"
    read new_name
    new_names[$file]=$new_name
  done

  for old_name in "${(ko)new_names[@]}"; do
    local new_name=$new_names[$old_name];
    [ "$old_name" = "$new_name" ] && local text_color=$TEXT_MUTED || local text_color=$TEXT_SUCCESS
    printf $text_color "${old_name} >> ${new_name}"
  done

  printf $TEXT_WARNING "Would you like to rename?"
  read_confirmation

  for old_name in "${(ko)new_names[@]}"; do
    mv -f $old_name $new_names[${old_name}]
  done
  printf $TEXT_SUCCESS "Renamed!"
;;

## [mkdir <directory>] ディレクトリを作成する
mkdir )
  ## --path パスを出力する
  if [ -n "${args[path]}" ]; then
    echo $args[1];
  else
    mkdir -p ${args[1]}
    printf $TEXT_SUCCESS "Successfully created directory."
    # ディレクトリ移動はサブシェル外で実行する
    exit $EXIT_CODE_WITH_ADDITION &> /dev/null
  fi
;;

## [open <environment>] Webサイトのホームを開く
## --alt 規定でないブラウザで開く
open )
  printf $TEXT_INFO "Choose a server to open."
  read_environment ${args[1]} && local env=${FUNCTION_REPLY}
  [ -n "${options[alt]}" ] && browser_options=(--alt) || browser_options=()
  open_in_browser "$(project_origin ${env})${URL_PATH_FRONT}" ${browser_options}
;;

## [admin <environment>] Webサイトの管理画面を開く
## --alt 規定でないブラウザで開く
admin )
  printf $TEXT_INFO "Choose a server to open."
  read_environment ${args[1]} && local env=${FUNCTION_REPLY}
  open_in_browser "$(project_origin ${env})${URL_PATH_ADMIN}" ${browser_options}
;;

## [diff] ベースブランチからの差分を確認
diff )
  case $args[1] in
  ### [diff main] メインブランチの最新コミットの差分を確認
  master | main )
    local target="${args[1]}..${args[1]}~1"
    ;;
  ### [diff copy] --copyオプションを付加する
  copy )
    local base_commit=$(git merge-base ${BASE_BRANCH} HEAD)
    local target="${base_commit}..HEAD"
    args[copy]="1"
    ;;
  * )
    local base_commit=$(git merge-base ${BASE_BRANCH} HEAD)
    local target="${base_commit}..HEAD"
    ;;
  esac

  ## --delete 削除されたファイルのみ表示する
  local filter="MAR"
  [[ -n "${args[delete]}" ]] && filter="D"

  local file_changes=$(git diff --name-only --diff-filter=${filter} ${target})
  if [ -z "$file_changes" ]; then
    printf $TEXT_DANGER "Nothing is changed."
    return
  fi

  printf $TEXT_INFO "$(echo $file_changes | grep -c '') files changed. (${target})"
  printf "${file_changes}\n"

  ## --copy 出力内容をクリップボードにコピーする
  if [[ -n "${args[copy]}" ]]; then
    echo ${file_changes} | pbcopy
    printf $TEXT_SUCCESS "差分ファイルリストをクリップボードにコピーしました"
  fi
;;

## [dist] 差分ファイルをdist出力する
## --commit 直前のコミットのみを対象とする
## --all ファイルを除外しない
## --copy 実行せずコマンドをコピーする
dist )
  local base_commit=$(git merge-base ${BASE_BRANCH} HEAD)

  case $args[1] in
  ### [dist ls] ファイル確認
  ls )
    printf $TEXT_WARNING "distフォルダを表示します"
    tree -a "${DEST_DIR}"
    ;;
  ### [dist rm] ファイル削除
  rm )
    rm -rf ${DEST_DIR} &> /dev/null
    mkdir ${DEST_DIR} &> /dev/null
    printf $TEXT_WARNING "distフォルダを削除しました"
    ;;
  ### [dist files] ファイル指定でコピー
  files )
    cd "${PROJECT_DIR}/" &> /dev/null

    local files=""
    printf $TEXT_INFO "対象ファイルを入力してください (空白行でEnterすると確定)"
    local file
    while true; do
      read file
      [ -z "$file" ] && break

      if [ -f $file ]; then
        files+="$file\n"
      else
        printf $TEXT_DANGER "File not found. (${file})"
      fi
    done

    if [[ -n "${options[copy]}" ]]; then
      echo $files | xargs -I {} echo "rsync -R {} ${DEST_DIR}" | pbcopy
      printf $TEXT_SUCCESS "指定ファイルの出力コマンドをクリップボードにコピーしました"
    else
      rm -rf ${DEST_DIR} &> /dev/null
      mkdir ${DEST_DIR}
      echo $files | xargs -I {} rsync -R {} ${DEST_DIR}
      printf $TEXT_WARNING "指定ファイルをdistフォルダにコピーしました"
    fi
    ;;
  * )
    cd "${PROJECT_DIR}/" &> /dev/null

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
      rm -rf ${DEST_DIR} &> /dev/null
      mkdir ${DEST_DIR}
      echo $files | xargs -I {} rsync -R {} ${DEST_DIR}
      printf $TEXT_WARNING "${target_name}をdistフォルダにコピーしました"
    fi
    ;;
  esac
;;

## [deploy] プロジェクトのソースをサーバーにリリースする
##          (dist: distフォルダをリリース deployer: リモートサーバーのDeployerを起動)
## -y デプロイ前の確認をスキップする
deploy )
  [ $2 ] && env=$2 || env="staging"

  case $DEPLOY_TYPE in
  dist )
    # DEPLOY_TYPE=dist distフォルダをリリース
    case $env in
    ### [deploy production] 本番サーバーにdistフォルダをリリースする (未実装)
    production )
      # /tmpディレクトリ固定のためファイルパスチェックなし
      echo $MESSAGE_PRODUCTION_ACCESS
    ;;
    ### [deploy staging] ステージングサーバーにdistフォルダをリリースする
    staging )
      [ -v $DEPLOY_TYPE ] && printf $TEXT_DANGER "Deploy type is not configured. (${env})" && return
    ;;
    esac

    tree $DEST_DIR

    if check_config_exists; then
      printf $TEXT_WARNING "設定ファイルが含まれています！"
    else
      if [ -z "$args[y]" ]; then
        printf $TEXT_WARNING "Would you like to deploy under dist to ${env}?"
        read_confirmation
      fi
    fi

    case $env in
      production )
        # 本番はtmpにアップロード
        rsync -hrv "${DEST_DIR}/${DEPLOY_DIST_TARGET_DIR}" "${SSH_NAME_PRODUCTION}:/tmp/releases/$(date +%Y%m%d)" --exclude='.DS_Store'
        ;;
      staging )
        # ステージングは直接アップロード
        rsync -hrvop "${DEST_DIR}/${DEPLOY_DIST_TARGET_DIR}" "${SSH_NAME_STAGING}:${APP_DIR}" --exclude='.DS_Store'
        ;;
    esac

    printf $TEXT_SUCCESS "Deployed!"
    ;;
  deployer )
    # DEPLOY_TYPE=deployer リモートのDeployerをSSHで起動
    local branch=${args[2]}

    local env=${args[1]}
    if [ $env ]; then
      env=$(parse_environment ${args[1]})
    else
      printf $TEXT_INFO "Choose a server to connect."
      read_selection local staging production && env=${FUNCTION_REPLY}
    fi

    case $env in
    production )
      [ -v $SSH_NAME_PRODUCTION ] && printf $TEXT_DANGER "SSH name is not configured. (${PROJECT_NAME} ${env})" && exit $EXIT_CODE_ERROR
      echo $MESSAGE_PRODUCTION_ACCESS

      printf $TEXT_WARNING "サーバー『${ssh_name}』にリリースしますか？"
      read_confirmation
      return
      ssh ${SSH_NAME_PRODUCTION} -t "cd ${APP_DIR}; bash --login"
      ;;
    staging )
      [ -v $SSH_NAME_STAGING ] && printf $TEXT_DANGER "SSH name is not configured. (${PROJECT_NAME} ${env})" && exit $EXIT_CODE_ERROR

      echo ""
      printf $TEXT_INFO "Choose a branch to deploy."
      read_git_branch && local branch=${FUNCTION_REPLY}

      printf $TEXT_INFO "Deployment to ${PROJECT_NAME}... (${branch} >> ${env})"

      return
      ssh ${SSH_NAME_STAGING} -t "cd ~/deployer; dep deploy staging --branch=${branch}"
      ;;
    local )
      printf $TEXT_MUTED "Cancelled."
      ;;
    esac


    ;;
  esac
;;

## [build] リリースファイルを作成する (未メンテナンス)
build )
  local base_commit="master"
  local release_commit="$BASE_BRANCH"

  # distフォルダをリセット
  rm -rf ${DEST_DIR} &> /dev/null
  mkdir ${DEST_DIR}

  case $2 in
  ## --copy 実行せずコマンドをコピーする
  --copy )
    git diff --name-only --diff-filter=MAR ${base_commit}..${release_commit} | grep -vE ^app/config | xargs -I {} echo "rsync -R {}  ${DEST_DIR}" | pbcopy
    printf $TEXT_WARNING "${BASE_BRANCH}ブランチからの差分ファイル出力用rsyncコマンドをコピーしました"
    ;;
  *)
    git diff --name-only --diff-filter=MAR ${base_commit}..${release_commit} | grep -vE ^app/config | xargs -I {} rsync -R {}  ${DEST_DIR}
    zip -r "${DEST_DIR}/${BACKLOG_PREFIX}.zip" "${DEST_DIR}/${DEPLOY_DIST_TARGET_DIR}"
    printf $TEXT_WARNING "${BASE_BRANCH}ブランチからの差分ファイルをdistフォルダにコピーしました"
    ;;
  esac
;;

## [ssh <environment>] SSH接続してアプリケーションルートに移動する
ssh )
  printf $TEXT_INFO "Choose a server to connect."
  read_environment ${args[1]} && local env=${FUNCTION_REPLY}
  printf $TEXT_INFO "Connecting to ${PROJECT_NAME} application root... (${env})"

  case $env in
  production )
    [ -v $SSH_NAME_PRODUCTION ] && printf $TEXT_DANGER "SSH name is not configured. (${PROJECT_NAME} ${env})" && exit 1
    echo $MESSAGE_PRODUCTION_ACCESS
    ssh ${SSH_NAME_PRODUCTION} -t "export PS1=\"\[\e[1;31m\][ssh:${SSH_NAME_PRODUCTION}] \[\e[0;31m\]\W\[\e[m\] \"; cd ${APP_DIR}; bash --login"
    ;;
  staging )
    [ -v $SSH_NAME_STAGING ] && printf $TEXT_DANGER "SSH name is not configured. (${PROJECT_NAME} ${env})" && exit 1
    ssh ${SSH_NAME_STAGING} -t "export PS1=\"\[\e[1;33m\][ssh:${SSH_NAME_STAGING}] \[\e[0;33m\]\W\[\e[m\] \"; cd ${APP_DIR}; bash --login"
    ;;
  local )
    if [[ "$VM_PLATFORM" == "vagrant" ]]; then
      cd_vagrant
      vagrant ssh -c 'cd "/var/www/$(ls /var/www | more)"; bash --login'
    else
      to doc bash web
    fi
    ;;
  esac
;;

## [sshkey <ssh_name>] 公開鍵をサーバーに設定する
sshkey )
  local ssh_name="${args[1]}"
  if [ -z "${ssh_name}" ]; then
    exit $EXIT_CODE_WRONG_ARGUMENT &> /dev/null
  fi

  printf $TEXT_SUCCESS "${args[1]}に追加する公開鍵を入力してください。"
  echo -n "public_key: "
  read public_key
  if [ -z "${public_key}" ]; then
    echo "公開鍵設定を中止しました。"
    return
  fi
  printf $TEXT_WARNING "サーバー『${ssh_name}』公開鍵を追加しますか？"
  read_confirmation

  ssh ${ssh_name} "mkdir -p ~/.ssh; echo "${public_key}" >> ~/.ssh/authorized_keys"
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
      echo \"cd ${APP_DIR}\"
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
;;

## [db] 仮想マシンのSQLに接続する
db )
  if [[ "$VM_PLATFORM" == "vagrant" ]]; then
    cd_vagrant
    vagrant ssh -c "psql ${@:2}"
  else
    local container="db"
    # docker-composeファイルから環境変数を読み取ってデータベースに接続する
    eval "local -A docker_env=($(docker_container_env))"
    if [ -n "${docker_env[MYSQL_USER]}" ]; then
      docker compose exec -it ${container} mysql -u ${docker_env[MYSQL_USER]} -D ${docker_env[MYSQL_DATABASE]} -p${docker_env[MYSQL_PASSWORD]}
    elif [ -n "${docker_env[POSTGRES_USER]}" ]; then
      docker compose exec -it ${container} psql -U ${docker_env[POSTGRES_USER]} -d ${docker_env[POSTGRES_DB]}
    else
      printf $TEXT_INFO_DARK "Docker database setting not found."
      to doc bash ${container}
    fi
  fi
;;

## [log <environment>] ログファイルを表示する
log )
  printf $TEXT_INFO "Choose a server to connect."
  read_environment ${args[1]} && local env=${FUNCTION_REPLY}

  case ${env} in
  production )
    local log_path=${LOG_FILE_PATH_PRODUCTION:-$LOG_FILE_PATH}
    ssh -t ${SSH_NAME_PRODUCTION} "tail -f ${log_path}"
    ;;
  staging )
    local log_path=${LOG_FILE_PATH_PRODUCTION:-$LOG_FILE_PATH}
    ssh -t ${SSH_NAME_STAGING} "tail -f ${log_path}"
    ;;
  local )
    [ $# = 2 ] && local filepath="$2" || local filepath="${LOG_FILE_PATH}"
    watch_vm_file "${filepath}"
  esac
;;

## [aws] プロジェクト名をプロファイル名としてAWS CLIを使用する
aws )
  aws --profile ${PROJECT_NAME} ${@:2}
;;

## [bl] Backlogをブラウザで開く
bl )
  [ ! $BACKLOG_PREFIX ] && printf $TEXT_DANGER "Backlog prefix is not configured. (${PROJECT_NAME})" && return 1
  local store_ini="${SCRIPT_DIR}/config/store.ini"
  local store_key_prefix="${PROJECT_NAME}_"

  case $args[1] in
  ### [bl <number>] 現在ブランチ名に応じて課題を開く
  [0-9]* )
    open "https://hotfactory.backlog.jp/view/${BACKLOG_PREFIX}-${args[1]}"
    ;;
  ### [bl ls] Backlog課題一覧を開く
  ls | l* )
    open "https://hotfactory.backlog.jp/find/${BACKLOG_PREFIX}"
    ;;
  ### [bl wiki] BacklogのWikiホームを開く
  wiki | w* )
    open "https://hotfactory.backlog.jp/wiki/${BACKLOG_PREFIX}/Home"
    ;;
  ### [bl set <project_id>] Backlog課題番号とブランチ名の対応リストを追加する
  set )
    if expr "${args[2]}" : "[0-9]*" &> /dev/null; then
      local branch_name=$(git rev-parse --abbrev-ref HEAD)
      local backlog_issue_key="${BACKLOG_PREFIX}-${args[2]}"

      set_ini "${store_key_prefix}${branch_name} = ${backlog_issue_key}" ${store_ini} --section=backlog_issue_key
      printf $TEXT_SUCCESS "Backlog課題番号を登録しました。[${branch_name} → ${backlog_issue_key}]"
    else
      exit $EXIT_CODE_WRONG_ARGUMENT &> /dev/null
    fi
    ;;
  * )
    local branch_name=$(git rev-parse --abbrev-ref HEAD)
    local stored_issue_key=$(parse_ini ${SCRIPT_DIR}/config/store.ini --section=backlog_issue_key --key=${store_key_prefix}${branch_name})

    if [ -n "$stored_issue_key" ]; then
      # iniに設定されたブランチがあれば課題を開く
      printf $TEXT_INFO "Found a backlog task relation. [${branch_name} → ${stored_issue_key}]"
      open "https://hotfactory.backlog.jp/view/${stored_issue_key}"
    elif [[ $branch_name == "${BACKLOG_PREFIX}-"* ]]; then
      local backlog_issue_key=$(echo $branch_name | sed "s/\(${BACKLOG_PREFIX}-[0-9]*\).*/\1/")
      # Backlog課題形式のブランチ名であれば課題を開く
      printf $TEXT_INFO "Open backlog project... (${backlog_issue_key})"
      open "https://hotfactory.backlog.jp/view/${backlog_issue_key}"
    else
      # 一致しなければ課題一覧を開く
      printf $TEXT_INFO "Open backlog projects index..."
      open "https://hotfactory.backlog.jp/find/${BACKLOG_PREFIX}"
    fi
    ;;
  esac
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

## [telescope] Laravel Telescopeをブラウザで開く
telescope )
  local browser_options=()
  [ -n "${options[alt]}" ] && browser_options+="--alt"
  open_in_browser "$(project_origin)/telescope/queries" ${browser_options}
;;

## [react <command>] React関連のコマンド群
react )
  case $args[1] in
  ### [react component] Reactのコンポーネントファイルを作成する
  component )
    local components_dir="${PROJECT_DIR}/src/components"
    if [ ! -e $component_dir ]; then
      printf $TEXT_DANGER "componentsディレクトリが見つかりませんでした"
      return
    fi

    echo -n "${COLOR_INFO}Component Name: ${COLOR_RESET}"
    local component_name
    read component_name
    if [ -z "$component_name" ]; then;
      return
    fi

    local target_dir="${components_dir}/${component_name}"
    if [ -e $target_dir ]; then
      printf $TEXT_DANGER "${target_dir}はすでに存在します"
      return
    fi
    mkdir $target_dir
    echo "import styles from './index.module.css';\n\ninterface Props {\n  children: React.ReactNode;\n}\n\n/** \n *\n * @param props.children - \n * @return\n */\nexport default function ${component_name}({ children }: Props) {\n  return (\n    <div className={styles.root}>\n      \n    </div>\n  );\n}" >> $target_dir/index.tsx
    echo ".root {\n  \n}" >> $target_dir/index.module.css
    printf $TEXT_SUCCESS "${component_name}コンポーネントを追加しました"
    ;;
  * )
    exit $EXIT_CODE_WRONG_ARGUMENT &> /dev/null
  esac
;;

## [swift <command>] Swift関連のコマンド群
swift )
  case $args[1] in
  ### [swift color <color_code>] 16進カラーコードをSwift形式に変換
  ### --digits=<number> 少数点桁数
  color )
    local hex=${args[2]#\#}
    local digits=${args[digits]:=3}

    # カラーコードが6桁でなければエラー
    if [[ $(echo -n $hex | wc -c | xargs) != 6 ]]; then
      printf $TEXT_DANGER "Color code must be specified in 6 digits."
      exit $EXIT_CODE_WRONG_ARGUMENT &> /dev/null
    fi
    # カラーコードを0〜255に変換
    local red=$((16#${hex:0:2}))
    local green=$((16#${hex:2:2}))
    local blue=$((16#${hex:4:2}))

    printf $TEXT_INFO "HEX  : #${hex}"
    printf $TEXT_INFO "CSS3 : rgb(${red}, ${green}, ${blue})"
    printf $TEXT_INFO "Swift: Color(red: $(math_division ${red} 255 -d=${digits}), green: $(math_division ${green} 255 -d=${digits}), blue: $(math_division ${blue} 255 -d=${digits}))"
    ;;
  * )
    exit $EXIT_CODE_WRONG_ARGUMENT &> /dev/null
  esac
;;

## [selenium] テストコード (TODO: 動作確認が終わり次第削除)
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

## [jstest] テストコード (TODO: 動作確認が終わり次第削除)
jstest )
  open "https://github.com/HOT-FACTORY/fv-app-ios//compare/FV_APP-334?expand=1"
  sleep 2


  browser_inner_text 'body'
  browser_input_value '[name="pull_request[title]"]' 'タイトルだぞ'
  browser_input_value '[name="pull_request[body]"]' 'いい"かあ'

;;

## [<etc>] アクション名が一致しなかった場合はアドオンファイルからアクションを実行
* )
  local addon_path="${SCRIPT_DIR}/config/addon.sh"
  if [ -f "${addon_path}" ]; then
    source ${addon_path}
    local exit_code=$?
    exit $exit_code &> /dev/null
  fi

  exit $EXIT_CODE_ACTION_NOT_FOUND &> /dev/null
  ;;
esac)

# サブシェル終了後のメインシェル処理 (終了コード2の場合)
local exit_code=$?
case ${exit_code} in
$EXIT_CODE_WRONG_ARGUMENT )
  printf $TEXT_DANGER "Wrong argument or option."
  to ${1} --help
  ;;
$EXIT_CODE_WITH_ADDITION )
  if [[ ${exit_code} == 10 ]]; then
    case $1 in
    refresh ) source $(to $@ --path) ;;
    mkdir | .. ) cd $(to $@ --path) &> /dev/null ;;
    esac
  fi
  ;;
$EXIT_CODE_ACTION_NOT_FOUND )
  printf $TEXT_DANGER "Undefined action. ($1)"
esac
}
