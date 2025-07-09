# toコマンドの定義
# 処理はサブシェルで実行
# @exit 0 成功
# @exit 1 失敗
# @exit 2 オプションや値が不正
# @exit $EXIT_CODE_WITH_ADDITION メインシェルで追加処理を実行
# @exit 27 アクションが見つからない
to() {
# 定数の読み込み (関数内ローカル)
source ~/.zsh/src/constants.sh

(
# サブシェル内で関数の終了ステータスが0以外の場合はスクリプトを中断
# サブシェル自体の戻り値は影響しない
set -e

# スクリプト内のカレントディレクトリ移動時に標準出力しない
cd() { builtin cd "$@" 1> /dev/null }

# 関数の読み込み
source $FUNCTIONS_PATH

# 引数とオプションを取得 ${args[1]}: 引数1 ${args[some_key]}: オプション(指定なしで値は1)
# $optionsは順次$argsに統一していく
local action=$1
parse_arguments ${@:2}; local -A args=(${(kv)ARGUMENTS_REPLY})
local -A options=(${(kv)args})

# --help オプションが指定された場合はヘルプメッセージを表示して完了
if [[ -n "${args[help]}" ]]; then
  print_heading "Personal Tool Script"
  print_help --action=${action}

  local addon=$(cat "${SCRIPT_DIR}/config/addon.sh" | text_subtract "^\(${PROJECT_NAME}.*\|[a-zA-Z].* | ${PROJECT_NAME}\) )$" "^[a-zA-Z].* )$")
  if [ -n "${addon}" ]; then
    print_heading "Project Addon Script"
    print_help ${addon} --action=${action}
  fi
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
  print_heading "Personal Tool Script"
  print_help

  # プロジェクト限定のスクリプト
  local addon=$(cat "${SCRIPT_DIR}/config/addon.sh" | text_subtract "^\(${PROJECT_NAME}.*\|[a-zA-Z].* | ${PROJECT_NAME}\) )$" "^[a-zA-Z].* )$")
  if [ -n "${addon}" ]; then
    print_heading "Project Addon Script"
    print_help ${addon}
  fi
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
  printf $TEXT_INFO "Enter project settings..."
  echo "${COLOR_INFO_DARK}PROJECT_NAME:${COLOR_RESET} ${PROJECT_NAME}"
  read_project_prop BASE_BRANCH $(git branch -r | grep HEAD | cut -d'/' -f3)
  read_project_prop BRANCH_PREFIX
  read_project_prop BACKLOG_PROJECT_KEY
  read_project_prop DEPLOY_TYPE "none: なし" "dist: distフォルダ経由でファイルリリース" "deployer: リモートサーバーのDeployer"
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
    read_selection_long "ls\tファイル一覧" "diff: 差分一覧" "export\t同期保存" "import\t同期読み込み" && sub_action=${FUNCTION_REPLY}
  fi

  case ${sub_action} in
  ### [sync ls] 反映中スクリプトの確認
  ls )
    ls -lohpTSG $SCRIPT_DIR
    ;;
  ### [sync diff] エクスポートされている設定ファイルとの差分を表示
  diff )
    diff -r ${EXPORT_DIR} ${SCRIPT_DIR} | sed "s/^\(-\{1,3\} .*\)$/${COLOR_DANGER}\1${COLOR_RESET}/" | sed "s/^\(+\{1,3\} .*\)$/${COLOR_SUCCESS}\1${COLOR_RESET}/"
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

## [backup] バックアップを更新する
backup )
  local from_paths=()
  local to_paths=()
  local path_keys=()

  # 設定INI backup_pathsセクションから対象パスを取得
  IFS=$'\n'
  local stored_paths=($(parse_ini ${SCRIPT_DIR}/config/store.ini --section=backup_paths))
  IFS=$DEFAULT_IFS
  printf $TEXT_INFO_DARK "Load backup settings."
  local stored_path
  for stored_path in ${stored_paths}; do
    local path_pair=$(echo ${stored_path} | sed 's/^[a-z_-]*=//')
    local path_key=$(echo ${stored_path} | sed 's/^\([a-z_-]*\)=.*$/\1/')
    local from_path=$(echo ${path_pair} | sed -r 's/^(.*[^\]) .*$/\1/' | sed 's/\\ / /g' | sed "s/^~/${HOME//\//\\/}/")
    if [ ! -d "${from_path}" ]; then
      printf $TEXT_MUTED "  ${path_key}: ${from_path} (Skipping because not exists.)"
      continue
    fi
    local to_path=$(echo ${path_pair} | sed -r 's/^.*[^\] (.*)$/\1/' | sed 's/\\ / /g' | sed 's/^\([^/]\)/\/\1/')

    path_keys+=("${path_key}")
    from_paths+=("${from_path}")
    to_paths+=("${to_path}")
    printf $TEXT_INFO "  ${path_key}: ${from_path} -> ${to_path}"
  done
  echo ''

  IFS=$'\n'
  local volumes=($(mount | grep '^[^ ]* on /Volumes' | sed -r 's/^.* on \/Volumes\/(.*) \([a-z ,]*\)$/\1/'))
  IFS=$DEFAULT_IFS
  if [ -z "${volumes}" ]; then
    printf $TEXT_WARNING "No volumes found."
    exit $EXIT_CODE_ERROR &> /dev/null
  fi

  printf $TEXT_INFO_DARK "Choose a volume to backup."
  read_selection_long "${volumes[@]}" && local volume=${FUNCTION_REPLY}

  # 設定INI backup_pathsセクションから対象パスを取得
  IFS=$'\n'
  local stored_paths=($(parse_ini ${SCRIPT_DIR}/config/store.ini --section=backup_paths))
  IFS=$DEFAULT_IFS

  printf $TEXT_INFO_DARK "Start backup to ${volume}."
  local i
  for ((i=1; i<=${#from_paths[@]}; i++)); do
    local from_path=${from_paths[$i]}
    local to_path=${to_paths[$i]}
    local path_key=${path_keys[$i]}
    local mode='Add only'
    local rsync_options=('-aru' "--exclude='/.git'" "--exclude='.DS_Store'")

    # _archive で終わるキーの場合は差分削除せず追加と更新のみ行う
    if [[ "${path_key}" != *_archive ]]; then
      mode=''
      rsync_options+=('--delete' '--prune-empty-dirs')
    fi

    local volume_path="/Volumes/${volume}${to_path}"
    if [ ! -d ${volume_path} ]; then
      printf $TEXT_WARNING "Target directory not found. Create it? (${volume_path})"
      read_confirmation
      mkdir -p ${volume_path}
    fi

    local progress_message="${from_path} → ${volume_path}"
    [ -n "${mode}" ] && progress_message="${progress_message} (${mode})"

    ## --verbose 進捗をファイルごとに表示する
    if [ -n "${args[d]}" ] || [ -n "${args[dry-run]}" ]; then
      printf $TEXT_INFO "${progress_message}"
    elif [ -n "${args[v]}" ] || [ -n "${args[verbose]}" ]; then
      printf $TEXT_INFO "${progress_message}"
      rsync ${rsync_options} -C --filter=":- .gitignore" --progress ${from_path} ${volume_path}
    else
      rsync ${rsync_options} -C --filter=":- .gitignore" ${from_path} ${volume_path} 1> /dev/null & progress ${progress_message}
    fi
  done
;;

## [timer] 経過時間計測を開始する
timer )
  ## --clean タイマーを全削除する
  if [ -n "$args[clean]" ]; then
    local process_count=$(ps | grep "sleep [0-9]\+.00000" | line_count)

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
      local count=$(docker stop $(docker ps -q) | line_count)
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
    browser_open $(github_url)
    ;;
  ### [git i] GitHubのIssuesページを開く
  issue|is|i )
    browser_open "$(github_url)/issues"
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
    ### --find=<filename> スタッシュの中からファイル名を検索する
    if [ -n "$args[find]" ]; then
      local target_objects=()
      printf $TEXT_INFO "Finding stash objects..."
      local objects=($(git stash list --format=%gd))
      for object in "${objects[@]}"; do
        local files=$(git stash show ${object} --name-only | grep $args[find])
        printf ${TEXT_INFO_DARK} "${object}"
        if [ -n "${files}" ]; then
          printf ${TEXT_MUTED} "${files}"
          target_objects+=(${object})
        else
          echo -n "${PREV_LINE}"
        fi
      done
      if [ -n "${target_objects[*]}" ]; then
        printf $TEXT_INFO "Choose a stash object."
        read_selection_long ${target_objects[@]} && local target_object=${FUNCTION_REPLY}

        local files=($(git stash show ${target_object} --name-only | grep $args[find]))
        for file in "${files[@]}"; do
          print_heading "${file}"
          printf ${TEXT_MUTED} "git diff HEAD..${target_object} -- ${file}"
          git diff HEAD..${target_object} -- ${file}
        done
      fi
      return
    fi

    ### --commit 現在のコミット内容をスタッシュに退避する
    if [ -n "$options[commit]" ]; then
      printf $TEXT_INFO "Stashing current commit..."
      local commit_message=$(git show -s --format=%s HEAD)
      git checkout --detach HEAD
      git reset --soft HEAD^
      git stash -m "[Tool Script] ${commit_message}"
      git checkout -
      return
    fi

    git stash --include-untracked
  ;;
  ### [git newpr] 新規にプルリクエストを作成する
  newpr )
    [[ "$BACKLOG_SPACE_ID" == *.* ]] && local backlog_hostname="${BACKLOG_SPACE_ID}" || local backlog_hostname="${BACKLOG_SPACE_ID}.backlog.jp"

    local branch_name=$(git rev-parse --abbrev-ref HEAD)
    if [[ $branch_name == "${BACKLOG_PROJECT_KEY}-"* ]]; then
      # Backlog課題形式のブランチ名であれば課題名を取得
      local backlog_issue_key=$(echo $branch_name | sed "s/\(${BACKLOG_PROJECT_KEY}-[0-9]*\).*/\1/")
      browser_open "https://${backlog_hostname}/view/${backlog_issue_key}"
      local task_name=$(browser_inner_text '#summary')
      browser_close
    fi

    local heading="##"

    ### --base <branch_name> プルリクエストのベースブランチを指定する
    if [ -n "$args[base]" ]; then
      local url="$(github_url)/compare/${args[base]}...${branch_name}?expand=1"
    else
      local url="$(github_url)/compare/${branch_name}?expand=1"
    fi


    browser_open ${url}
    browser_set_input '[name="pull_request[title]"]' "${branch_name} ${task_name}"
    browser_set_input '[name="pull_request[body]"]' "${heading} Backlog\nhttps://${backlog_hostname}/view/${backlog_issue_key}\n\n${heading} 対応内容\n"
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
  if [[ $2 =~ ^[0-9] ]]; then
    local branch_name="${BRANCH_PREFIX}$2"
  else
    local branch_name="$2"
  fi
  git checkout -b ${branch_name} &> /dev/null
  echo "ブランチ『${branch_name}』を作成しました"
;;

## [rename] ディレクトリ内のファイル名一括変更
rename )
  IFS=$'\n'
  local items=($(ls -1F))
  IFS=$DEFAULT_IFS

  ## --dir ディレクトリ内のファイルではなくディレクトリを対象にする
  [ -n "${args[dir]}" ] && local directory_mode=true || local directory_mode=false

  local files=()
  local item
  for item in "${items[@]}"; do
    [[ "${item}" == */ ]] && local is_directory=true || local is_directory=false
    [ ${is_directory} = ${directory_mode} ] && files+=(${item})
  done

  if [ -z "${files}" ]; then
    printf $TEXT_WARNING "No files found in current directory."
    return $EXIT_CODE_ERROR &> /dev/null
  fi

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
  browser_open "$(project_origin ${env})${URL_PATH_FRONT}" ${browser_options}
;;

## [admin <environment>] Webサイトの管理画面を開く
## --alt 規定でないブラウザで開く
admin )
  printf $TEXT_INFO "Choose a server to open."
  read_environment ${args[1]} && local env=${FUNCTION_REPLY}
  [ -n "${options[alt]}" ] && browser_options=(--alt) || browser_options=()
  browser_open "$(project_origin ${env})${URL_PATH_ADMIN}" ${browser_options}
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
      printf $TEXT_WARNING "$(git log -1 --format='%as: %s')"
    else
      local base_commit=$(git merge-base ${BASE_BRANCH} HEAD)
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

    if [ -e "${DEST_DIR}/config" ] || [ -e "${DEST_DIR}/dist/vagrant" ]; then
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
      local ssh_name=$SSH_NAME_PRODUCTION

      [ -v $SSH_NAME_PRODUCTION ] && printf $TEXT_DANGER "SSH name is not configured. (${PROJECT_NAME} ${env})" && exit $EXIT_CODE_ERROR
      echo $MESSAGE_PRODUCTION_ACCESS

      local branch="master"
      printf $TEXT_INFO "Would you like to deploy to ${PROJECT_NAME}... (${branch} >> ${env})"
      read_confirmation
      ssh ${SSH_NAME_PRODUCTION} -t "cd ~/deployer; ~/.config/composer/vendor/bin/dep deploy"
      ;;
    staging )
      local ssh_name=$SSH_NAME_STAGING
      [ -v $SSH_NAME_STAGING ] && printf $TEXT_DANGER "SSH name is not configured. (${PROJECT_NAME} ${env})" && exit $EXIT_CODE_ERROR

      printf $TEXT_INFO "Deployment to ${PROJECT_NAME}... (${branch} >> ${env})"
      printf $TEXT_INFO "Choose a branch to deploy."
      read_git_branch && local branch=${FUNCTION_REPLY}
      ssh ${SSH_NAME_STAGING} -t "cd ~/deployer; ~/.config/composer/vendor/bin/dep deploy --branch=${branch}"
      ;;
    * )
      printf $TEXT_MUTED "Cancelled."
      ;;
    esac
  ;;
  addon )
    local addon_path="${SCRIPT_DIR}/config/addon.sh"
    if [ -f "${addon_path}" ]; then
      source ${addon_path}
      local exit_code=$?
      exit $exit_code &> /dev/null
    fi
  ;;
  * )
    exit $EXIT_CODE_ERROR &> /dev/null
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

## [node] Node.jsのパッケージマネージャの操作を行う
node | n )
  # 直近のpackage.jsonのあるディレクトリを探す
  local node_root=$(node_root)
  local node_action=${args[1]}

  # VoltaのNodeのバージョンを.node-versionファイルから切り替える
  # if [ -f ${node_root}/.node-version ]; then
  #   local version=$(cat ${node_root}/.node-version)
  #   volta install node@${version} --quiet
  # fi

  # プロジェクトで使用しているパッケージマネージャを自動で判定
  if [ -f "${node_root}/package-lock.json" ]; then
    local pm="npm"
  elif [ -f "${node_root}/yarn.lock" ]; then
    local pm="yarn"
  elif [ -f "${node_root}/pnpm-lock.yaml" ]; then
    local pm="pnpm"
  fi
  [ "${pm}" = "npm" ] && local is_npm=true || local is_npm=false
  if [ -z "${pm}" ]; then
    printf $TEXT_DANGER "Package lock file not found. (${node_root})"
    exit $EXIT_CODE_ERROR &> /dev/null
  fi

  # コマンドを指定しない場合はScript設定から選択する
  if [ -z "${node_action}" ]; then
    local -a scripts=($(awk '/"scripts"/,/^ *}/' "package.json" | grep ' *": "' | sed 's/ *\"\([^\"]*\)\":.*/\1/'))
    read_selection_long ${scripts[@]} && node_action=${FUNCTION_REPLY}
  fi

  local command="";
  case ${node_action} in
  ### [node install] パッケージのインストール
  i | install | add )
    ### --reload パッケージのキャッシュを削除する
    if [ -n "${args[reload]}" ]; then
      rm -rf ${node_root}/node_modules
      printf $TEXT_MUTED "Node modules deleted."
    fi

    if [ -n "${args[2]}" ]; then
      ${is_npm} && command="install" || command="add"
    else
      command="install"
    fi
  ;;
  ### [node uninstall] パッケージのアンインストール
  uninstall | remove )
    ${is_npm} && $command="uninstall" || $command="remove"
  ;;
  ### [node update] ロックファイルのバージョンアップ
  update )
    ${is_npm} && command="update" || command="upgrade"
  ;;
  ### [node upgrade] パッケージのアップグレード
  upgrade )
    local option=""
    [ -n "${args[latest]}" ] && option="--latest"
    if ${is_npm}; then
      npm-check-updates -i ${args[@:2]} ${option}
    else
      [ "${pm}" = "yarn" ] && yarn upgrade-interactive ${args[@:2]} ${option} || pnpm update -i ${args[@:2]} ${option}
    fi
  ;;
  ### [node exec] パッケージを実行
  exec )
    command="exec"
  ;;
  ### [node run] package.jsonのスクリプトを実行
  run )
    ${is_npm} && command="run" || command=""
  ;;
  ### [node dev] package.jsonのスクリプトから dev もしくは start を実行
  dev )
    command="start"
    if awk '/"scripts"/,/\}/' "${node_root}/package.json" | grep -q '^ *"dev":'; then
      ${is_npm} && command="run dev" || command="dev"
    fi

    # エディタを開く
    which code &> /dev/null && code ${node_root}
  ;;
  ### [node version] VoltaでプロジェクトのNodeバージョンを固定
  version )
    ### [node version install] Nodeをインストール
    if [ "$args[2]" = "install" ]; then
      printf $TEXT_INFO "Choose a Node.js version to install."
      # local versions=($(curl -s https://nodejs.org/dist/index.json | grep -o '"version": *"v[^"]*"' | sed -E 's/"version": *"v([^"]*)"/\1/' | sort -Vr | awk -F. '!seen[$1]++'))
      local versions=($(nodenv install -l | grep '^[0-9]'))
      read_selection_long "${versions[@]}" && local version=${FUNCTION_REPLY}
      # volta install node@${version}
      nodenv local ${version}
      printf $TEXT_SUCCESS "Node.js ${version} has been installed."
      return
    fi

    printf $TEXT_INFO "Choose the Node.js version for this project."
    # local versions=($(volta list node --format plain | sed -n 's/.*@\([0-9.]*\).*/\1/p'))
    local versions=($(nodenv versions | sed 's/^[* ] \([^ ]*\).*/\1/'))
    read_selection_long "${versions[@]}" && local version=${FUNCTION_REPLY}

    echo "${version}" > ${node_root}/.node-version
    printf $TEXT_SUCCESS "Node.js local version: ${version}"
    return
  ;;
  * )
    ${is_npm} && command="run ${node_action}" || command="${node_action}"
  esac

  printf $TEXT_MUTED "$ ${pm} ${command} ${args[@:2]}"
  if [ -n "${command}" ]; then
    ${pm} $(echo $command[@]) ${args[@:2]}
  fi
;;

## [curl <url>] APIリクエストを実行する
curl )
  local url=${args[1]}
  local method="GET"
  local parameters=""
  if [ -z "${url}" ]; then
    echo -n "${COLOR_INFO}URL: ${COLOR_RESET}"
    read url
    if [ -z "${url}" ]; then
      printf $TEXT_DANGER "URL is empty."
      exit $EXIT_CODE_ERROR &> /dev/null
    fi

    echo "${COLOR_INFO}Method:${COLOR_RESET}"
    read_selection "GET" "POST" && method=${FUNCTION_REPLY}

    if [ "${method}" != "GET" ]; then
      echo "${COLOR_INFO}Parameters:${COLOR_RESET} ${COLOR_MUTED}(空白行でEnterすると確定)${COLOR_RESET}"
      local line
      while true; do
        read line
        [ -z "${line}" ] && break
        parameters+="${line}\n"
      done
    fi
  else
    echo "${COLOR_INFO}URL:${COLOR_RESET} ${url}"
    echo "${COLOR_INFO}Method:${COLOR_RESET} ${method}"
  fi

  local command="curl -sL -X ${method} '${url}'"
  [ -n "${parameters}" ] && local command="curl -sL '${url}' -X ${method} -H 'Content-Type: application/json' -d '${parameters}'"
  printf $TEXT_MUTED ${command}
  local res=$(eval ${command})
  printf ${TEXT_INFO} "Response: "
  echo ${res} | python3 -m json.tool | sed "s/\"\([^\"]*\)\":/${COLOR_NOTICE}\1${COLOR_RESET}:/"
  echo ""
;;

## [aws] プロジェクト名をプロファイル名としてAWS CLIを使用する
aws )
  aws --profile ${PROJECT_NAME} ${@:2}
;;

## [bl] Backlogをブラウザで開く
bl )
  [[ "$BACKLOG_SPACE_ID" == *.* ]] && local backlog_hostname="${BACKLOG_SPACE_ID}" || local backlog_hostname="${BACKLOG_SPACE_ID}.backlog.jp"

  # プロジェクトキーの設定がなければ設定を開始
  if [ ! $BACKLOG_PROJECT_KEY ]; then
    printf $TEXT_DANGER "Backlog prefix is not configured. (${PROJECT_NAME})"
    read_project_prop BACKLOG_PROJECT_KEY && BACKLOG_PROJECT_KEY=${FUNCTION_REPLY}
    [ ! $BACKLOG_PROJECT_KEY ] && exit $EXIT_CODE_ERROR &> /dev/null
  fi
  local store_ini="${SCRIPT_DIR}/config/store.ini"
  local store_key_prefix="${PROJECT_NAME}_"

  case $args[1] in
  ### [bl <number>] 現在ブランチ名に応じて課題を開く
  [0-9]* )
    browser_open "https://${backlog_hostname}/view/${BACKLOG_PROJECT_KEY}-${args[1]}"
    ;;
  ### [bl ls] Backlog課題一覧を開く
  ls | l* )
    browser_open "https://${backlog_hostname}/find/${BACKLOG_PROJECT_KEY}"
    ;;
  ### [bl wiki] BacklogのWikiホームを開く
  wiki | w* )
    browser_open "https://${backlog_hostname}/wiki/${BACKLOG_PROJECT_KEY}/Home"
    ;;
  ### [bl set <project_id>] Backlog課題番号とブランチ名の対応リストを追加する
  set )
    if expr "${args[2]}" : "[0-9]*" &> /dev/null; then
      local branch_name=$(git rev-parse --abbrev-ref HEAD)
      local backlog_issue_key="${BACKLOG_PROJECT_KEY}-${args[2]}"

      set_ini "${store_key_prefix}${branch_name} = ${backlog_issue_key}" ${store_ini} --section=backlog_issue_key
      printf $TEXT_SUCCESS "Backlog課題番号を登録しました。[${branch_name} → ${backlog_issue_key}]"
    else
      exit $EXIT_CODE_WRONG_ARGUMENT &> /dev/null
    fi
    ;;
  * )
    local branch_name=$(git rev-parse --abbrev-ref HEAD)
    local stored_issue_key=$(parse_ini ${SCRIPT_DIR}/config/store.ini --section=backlog_issue_key --key=${store_key_prefix}${branch_name})

    [[ "$BACKLOG_SPACE_ID" == *.* ]] && local backlog_hostname="${BACKLOG_SPACE_ID}" || local backlog_hostname="${BACKLOG_SPACE_ID}.backlog.jp"

    if [ -n "$stored_issue_key" ]; then
      # iniに設定されたブランチがあれば課題を開く
      printf $TEXT_INFO "Found a backlog task relation. [${branch_name} → ${stored_issue_key}]"
      browser_open "https://${backlog_hostname}/view/${stored_issue_key}"
    elif [[ $branch_name == "${BACKLOG_PROJECT_KEY}-"* ]]; then
      local backlog_issue_key=$(echo $branch_name | sed "s/\(${BACKLOG_PROJECT_KEY}-[0-9]*\).*/\1/")
      # Backlog課題形式のブランチ名であれば課題を開く
      printf $TEXT_INFO "Open backlog project... (${backlog_issue_key})"
      browser_open "https://${backlog_hostname}/view/${backlog_issue_key}"
    else
      # 一致しなければ課題一覧を開く
      printf $TEXT_INFO "Open backlog projects index..."
      browser_open "https://${backlog_hostname}/find/${BACKLOG_PROJECT_KEY}"
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
  browser_open "$(project_origin)/telescope/queries" ${browser_options}
;;

## [react <command>] React関連のコマンド群
react )
  case $args[1] in
  ### [react component] Reactのコンポーネントファイルを作成する
  component )
    local node_root=$(node_root)

    local components_dir="${node_root}/src/components"
    if [ ! -e $components_dir ]; then
      printf $TEXT_DANGER "componentsディレクトリが見つかりませんでした"
      return
    fi

    echo -n "${COLOR_INFO}Component Name: ${COLOR_RESET}"
    local component_name
    read component_name
    if [ -z "$component_name" ]; then;
      return
    fi

    local jsx_count=$(find ${components_dir} -maxdepth 1 -type f -name "*.js" -o -name "*.jsx" -o -name "*.tsx" | wc -l)
    local dir_count=$(find ${components_dir} -maxdepth 1 -type d | wc -l)
    if [ ${dir_count} -gt ${jsx_count} ]; then
      local file_name="index"
      local target_dir="${components_dir}/${component_name}"
      if [ -e $target_dir ]; then
        printf $TEXT_DANGER "${target_dir}はすでに存在します"
        return
      fi
      mkdir $target_dir
    else
      local file_name="${component_name}"
      local target_dir="${components_dir}"
    fi

    echo "import styles from './index.module.css';\n\ninterface Props {\n  children: React.ReactNode;\n}\n\n/** \n *\n * @param props.children - \n * @return\n */\nexport default function ${component_name}({ children }: Props) {\n  return (\n    <div className={styles.root}>\n      \n    </div>\n  );\n}" >> ${target_dir}/${file_name}.tsx
    echo ".root {\n  \n}" >> ${target_dir}/${file_name}.module.css
    printf $TEXT_SUCCESS "${component_name}コンポーネントを追加しました"
    ;;

  ### [react component] Reactのコンポーネントファイルを作成する
  component2 )
    local components_dir="${PROJECT_DIR}/src/components"
    if [ ! -e $components_dir ]; then
      printf $TEXT_DANGER "componentsディレクトリが見つかりませんでした"
      return
    fi

    echo -n "${COLOR_INFO}Component Name: ${COLOR_RESET}"
    local component_name
    read component_name
    if [ -z "$component_name" ]; then;
      return
    fi

    local jsx_count=$(find ${components_dir} -maxdepth 1 -type f -name "*.js" -o -name "*.jsx" -o -name "*.tsx" | wc -l)
    local dir_count=$(find ${components_dir} -maxdepth 1 -type d | wc -l)

    if [ ${dir_count} -ge ${jsx_count} ]; then
      local jsx_dir="${components_dir}/${component_name}"
      local css_dir="${components_dir}/${component_name}"
      local file_name="index"
      if [ -e $jsx_dir ]; then
        printf $TEXT_DANGER "${jsx_dir}はすでに存在します"
        return
      fi
      # mkdir $jsx_dir
    else
      local jsx_dir="${components_dir}"
      local css_dir="${PROJECT_DIR}/src/assets/styles"
      local file_name="${component_name}"
      local css_import_path="./index.module.css"
    fi
    echo "-----"
    local jsx_path="${jsx_dir}/${file_name}.$(existing_file_extension ${jsx_dir} tsx ts jsx js)"
    local css_path="${css_dir}/${file_name}.$(existing_file_extension ${css_dir} module.scss module.css scss css)"

    echo ${jsx_path} ${css_path}
    return

    echo "import styles from '${css_import_path}';\n\ninterface Props {\n  children: React.ReactNode;\n}\n\n/** \n *\n * @param props.children - \n * @return\n */\nexport default function ${component_name}({ children }: Props) {\n  return (\n    <div className={styles.root}>\n      \n    </div>\n  );\n}" >> ${tsx_path}
    echo ".root {\n  \n}" >> ${css_path}
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
  clean )
    printf $TEXT_DANGER "Xcodeのキャッシュを削除します"
    read_confirmation

    rm -rf ~/Library/Caches/com.apple.dt.Xcode
    rm -rf ~/Library/Developer/Xcode/DerivedData
    rm -rf ~/Library/Developer/Xcode/UserData/Previews
    rm -rf ~/Library/Developer/XCPGDevices
    rm -rf ~/Library/Developer/Xcode/iOS\ DeviceSupport
    ;;
  * )
    exit $EXIT_CODE_WRONG_ARGUMENT &> /dev/null
  esac
;;

## [bing <message>] Bing AI Copilotを操作する
bing )
  local message=""
  printf $TEXT_INFO "Bing AIへのメッセージを入力してください (空白行でEnterすると確定)"
  local line
  while true; do
    read line
    [ -z "${line}" ] && break
    message+="${line}\n"
  done

  browser_open "https://copilot.microsoft.com" --skip
  browser_javascript_element "#userInput" "element.click();"
  sleep 0.5
  browser_set_input "#userInput" "$(echo ${message})"
  osascript -l JavaScript -e "function run(arguments) {
    const se = Application('System Events');
    se.keystroke('.');
    se.keyCode(51);
  }"
  sleep 0.5
  browser_javascript_element "[title=\"メッセージの送信\"]" "element.click();"
;;

## [browser] ブラウザに関する操作
browser )
  case $args[1] in
  ### [browser crawl] 指定のURLからリンクされている同一ドメインのページに再起的にアクセスする
  ### --exclude=<pattern> URLに部分一致したら対象から除外する
  crawl )
    local urls=("${args[2]}")
    local -A hash=()
    local index=1

    while [ ${#urls[@]} -ge ${index} ]; do
      local url="${urls[${index}]}"
      browser_open --sync --background ${urls[${index}]} --mode=new

      local new_urls=($(browser_javascript_sync_background "
        const [excludes = ''] = arguments;
        const urls = new Set();

        document.querySelectorAll('a').forEach((link) => {
          let url;
          try { url = new URL(link.href) } catch (e) { return }
          if (url.hostname !== location.hostname
            || /\.(jpe?g|png|gif|pdf)$/.test(url.pathname.split('/').at(-1))
            || (excludes && url.pathname.includes(excludes))) return;

          urls.add(\`\${url.origin}\${url.pathname}\${url.search}\`);
        });

        [...document.forms].forEach((form) => {
          if (form.method !== 'get') return;
          let url;
          try { url = new URL(form.action) } catch (e) { return }
          urls.add(\`\${url.origin}\${url.pathname}\${url.search}\`);
        });

        return urls.size ? [...urls].join('\n') : 'empty';
      " ${args[exclude]} "${urls}"))

      [[ ${new_urls} != "empty" ]] && urls=($(printf "%s\n" "${urls[@]}" "${new_urls[@]}" | awk '!seen[$0]++'))
      index=$(( $index + 1 ))
    done

    urls=($(echo "${urls[*]}" | tr ' ' '\n' | sort))
    printf $TEXT_INFO ${urls}
  ;;
  ### [browser script] 表示中のページからフォーム入力用のスクリプトコードを自動生成する
  script )
    local script=$(cat <<- 'EOS'
      const map = new Map();
      const selectedInputName = new Set();
      [...document.forms[0].elements].forEach((input) => {
        if (!input.name) return;

        switch (input.type) {
        case 'hidden':
        case 'submit':
        case 'button':
          break;
        case 'radio':
        case 'checkbox':
          if (selectedInputName.has(input.name)) return;

          let prevValue = '';
          if (input.checked) {
            selectedInputName.add(input.name);
          } else {
            prevValue = map.get(input.name);
          }
          map.set(input.name, prevValue ? `${prevValue} '${input.value}'` : `browser_set_input '[name="${input.name}"]' '${input.value}'`);
          break;
        case 'select-one':
          const options = [...input.options];
          let selection = input.options[input.selectedIndex].getAttribute('value');
          if (!selection) {
            selection = options.find((option) => option.getAttribute('value'))?.getAttribute('value') ?? '';
          };

          map.set(input.name, `browser_set_input '[name="${input.name}"]' '${selection}'`);
          break;
        default:
          map.set(input.name, `browser_set_input '[name="${input.name}"]' '${input.value}'`);
        }
      });

      return [`browser_open '${location.href}'`, ...map.values()].join('\n');
		EOS
    )
    echo -n ${COLOR_INFO_DARK}
    browser_javascript_sync ${script}
    echo ${COLOR_RESET}
  ;;
  '' )
    browser_focus
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
  case $1 in
  refresh ) source $(to $@ --path) ;;
  mkdir | .. ) cd $(to $@ --path) &> /dev/null ;;
  esac
  ;;
$EXIT_CODE_ACTION_NOT_FOUND )
  printf $TEXT_DANGER "Undefined action. ($1)"
  ;;
$EXIT_CODE_TIMEOUT )
  printf $TEXT_DANGER "Action timed out. ($1)"
  ;;
esac
}
