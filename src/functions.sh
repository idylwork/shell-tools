# スクリプト関数ファイル
# 汎用定数が読み込まれている前提の関数あり

# マルチバイトを2文字として文字丸めする
# @param string 文字列
# @param number 最大文字数
text_ellipses() {
  local text=""
  local count=0
  for (( i=0; i<${#1}; i++ )); do
    local char=${1:$i:1}
    echo -n $char

    text+=$char
    if expr "$char" : "^[ -~]$" &> /dev/null; then
      count=$(( $count + 1 ))
    else
      count=$(( $count + 2 ))
    fi
    [ $count -ge $2 ] && break
  done
  echo $text
}

# 環境名の入力揺れを吸収する
# @param string 環境名
# @returns string 環境名 [local: ローカル, staging: ステージング, production: 本番]
parse_environment() {
  case $args[1] in
  production|p ) echo 'production';;
  staging|s ) echo 'staging';;
  * ) echo 'local';;
  esac
}

# 引数とオプションを読み取り連想配列として返す
# ARGUMENTS_REPLYを使わない場合は、zshの連想配列の仕様上分割されてしまうため、改行を含む引数には対応していません
# evalを使用すると受け取ることができます
# @param string $@ 全引数
# @returns $ARGUMENTS_REPLY ([string]=string) 数字のキーに引数、文字列のキーにオプション
# @example
#   parse_arguments ${@}; local -A args=(${(kv)ARGUMENTS_REPLY})
parse_arguments() {
  ARGUMENTS_REPLY=()
  local index=1
  for i in $(seq $#); do
    local key=""
    local value=""

    local argument=${${@}[$i]}
    case $argument in
    - )
      # 引数
      key=$((index++))
      value=${argument}
      ;;
    -[0-9]=* | -[0-9][0-9]=* | --[0-9]=* | --[0-9][0-9]=* )
      # 数値キーのオプションはインデックスを上書きしないようにハイフンを削除しない
      local option_text=${argument}
      key=${option_text%=*}
      [[ ${option_text} == *=* ]] && value=${option_text#*=} || value=1
      ;;
    --*)
      # オプション
      local option_text=${argument#--}
      key=${option_text%=*}
      [[ ${option_text} == *=* ]] && value=${option_text#*=} || value=1
      ;;
    -* )
      # オプション
      local option_text=${argument#-}
      key=${option_text%=*}
      [[ ${option_text} == *=* ]] && value=${option_text#*=} || value=1
      ;;
    '' )
      continue
      ;;
    * )
      # 引数
      key=$((index++))
      value=${argument}
      ;;
    esac

    ARGUMENTS_REPLY[${key}]=${value}
  done
}

pretty_json() {
  python3 -m json.tool | sed "s/^\( *\)\"\([^\"]*\)\": /\1${COLOR_SUCCESS}\2: ${COLOR_RESET}/g"
}

# 直前の並列処理にプログレス表示を追加する
# @param string $1 メッセージ
# @param string $2 完了メッセージ
# @example
#   example_command 1> /dev/null & progress "Loading..."
#   echo "Complete!"
progress() {
  local pid=$!
  local message=$1
  local length=5
  local duration=1

  while [[ "$(ps -o pid -p ${pid})" == *${pid}* ]]; do
    echo -n "\r${COLOR_SUCCESS}$(printf '%0.s█' {1..${duration}})${COLOR_MUTED}$([ ${duration} != ${length} ] && printf '%0.s█' {$(( ${duration} + 1 ))..${length}})${COLOR_RESET} ${message} ${COLOR_DANGER}"
    duration=$(( ${duration} % ${length} + 1 ))
    sleep 0.3
  done

  echo -n "${COLOR_RESET}\r$(printf '%0.s ' {0..$(( ${#message} + ${length} ))})  \r"
  echo "$(printf '%0.s ' {0..${length}})${message}"
}

# 第1引数をベースにディレクトリパスをあいまい検索する
# @param string $1 ベースディレクトリ
# @param string $2 あいまい検索文字列 (引数追加でディレクトリを深掘り)
# @returns string ディレクトリパス
fuzzy_dir_search() {
  local target_path=$1

  # まず前方一致で確認、一致がない場合は条件をあいまいにして再検索しながら引数の数だけ深掘りしていく
  for arg in ${@:2}; do
    # 前方一致
    local prefix_regex="^${arg}.*"
    local next_dir=$(ls $target_path | grep -s -m1 $prefix_regex)
    # 前方スネークケース・ケバブケース
    if [ -z $next_dir ]; then
      local snake_regex="^$(echo ${arg} | sed 's|.|&[_-]*|g')"
      local next_dir=$(ls $target_path | grep -s -m1 $snake_regex)
    fi
    # 前方あいまい検索
    if [ -z $next_dir ]; then
      local fuzzy_regex="^$(echo ${arg} | sed 's|.|&.*|g')"
      local next_dir=$(ls $target_path | grep -s -m1 $fuzzy_regex)
    fi
    # あいまい検索
    if [ -z $next_dir ]; then
      local fuzzy_regex="$(echo ${arg} | sed 's|.|&.*|g')"
      local next_dir=$(ls $target_path | grep -s -m1 $fuzzy_regex)
    fi

    target_path+="/${next_dir}"
  done
  echo ${target_path}
}

# プロジェクトルートパスを取得 (GitルートかWorkspace直下をルートとする)
get_project_root() {
  local current_dir=$(pwd)

  local git_root=$(git rev-parse --show-toplevel 2> /dev/null)
  if [ -n "${git_root}" ]; then
    # Gitの設定があればGitのルートディレクトリ
    echo ${git_root}
  else
    case ${current_dir} in
    ${WORKSPACE}/* )
      # ワークスペース配下ならとりあえず直下として扱う
      local dir_name=$(echo ${current_dir} | sed -e "s|${WORKSPACE}/\([^/]*\).*$|\1|")
      echo "${WORKSPACE}/${dir_name}"
      ;;
    * )
      echo ${current_dir}
    esac
  fi
}

# INIファイルから項目を取得
# @param string $1 INIファイルパス
# @option --section=<string> 対象とするセクション名 (未指定の場合は全項目)
# @option --key=<string> 特定の項の値を出力する
# @returns string 変数宣言コード
# @example source <(parse_ini ./example.ini --section=example_section | sed "s/^ */local /g")
# @example parse_ini ./example.ini --key=EXAMPLE
parse_ini() {
  parse_arguments ${@}; local -A args=(${(kv)ARGUMENTS_REPLY})

  # ファイル名未指定では読み込みしない
  if [ -z "${args[1]}" ]; then
    return
  fi

  # 対象項目を取得
  if [ -n "${args[section]}" ]; then
    # Section constants
    local attributes=$(cat ${args[1]} | text_after "\[${args[section]}\]" | sed -e '1d' | sed -n '/^\[.*\]$/q;p')
  else
    # All constants
    local attributes=$(grep -v "\[.*\]" ${args[1]})
  fi
  if [ -z "${attributes}" ]; then
    return
  fi

  if [ -n "${args[key]}" ]; then
    # キーが指定された場合は値のみを返す
    echo ${attributes} | grep "^ *${args[key]} *=" | head -1 | sed "s/^ *${args[key]} *= *//" | sed 's/^"\(.*\)"$/\1/'
  else
    # 空白行を除外・イコール周辺のスペース削除して項目行を出力
    echo ${attributes} | sed '/^$/d' | sed 's/ *= */=/g'
  fi
}

# INIファイルに項目を追加する
# @param string $1 追記内容
# @param string $2 INIファイルパス
# @option --section=<string> 対象とするセクション名 (未指定の場合は全項目)
# @example set_ini "example_key = example_value" ./example.ini --section=example_section
set_ini() {
  parse_arguments ${@}; local -A args=(${(kv)ARGUMENTS_REPLY})
  [ -n "${args[section]}" ] && local addition="  ${args[1]}" || local addition=${args[1]}

  # 対象セクションの始めと終わりの行を特定する
  local lines=$(cat ${args[2]} | grep -n "\[.*\]")
  local section_start=0
  local section_end=0
  if [ -n "$args{1}" ]; then
    local is_matched=false
    while read line; do
      if "${is_matched}"; then
        local section_end=${line%%:*}
        break
      fi

      local section=$(echo ${line#*:} | sed "s/^\[\(.*\)\]$/\1/")
      if [[ "${section}" == "${args[section]}" ]]; then
        local section_start=${line%%:*}
        local is_matched=true
      fi
    done <<< "${lines}"
  fi

  # 対象セクションの次のセクションが見つからなければファイル末尾に書き込み
  if [[ ${section_end} == 0 ]]; then
    section_end=$(cat ${args[2]} | wc -l | sed -e 's/ //g')
    if [[ "${is_matched}" == "false" && -n "${args[section]}" ]]; then
      section_start=${section_end}
    fi
  fi

  # 空白行を無視
  while [ -z "$(cat ${args[2]} | sed -n $((section_end - 1))P)" ]; do
    cat ${args[2]} | sed -n $((section_end - 1))P
    section_end=$((${section_end} + 1))
  done

  # 重複項目をチェック
  local section_text=$(sed -n $((section_start + 1)),${section_end}p ${args[2]})
  local duplicate_offset=$(echo ${section_text} | awk '{print $0}' | grep -n "^ *${args[1]%=*} *= *" | head -1 | sed "s/^\([0-9]\{1,\}\).*$/\1/")
  if [ ${duplicate_offset} ]; then
    # すでにキーがある場合は行を上書き
    local target_row=$((${duplicate_offset} + ${section_start}))
    local sed_command="c"
  elif [[ "${is_matched}" == "false" && -n "${args[section]}" ]]; then
    # セクションがない場合はセクションを追加
    sed -i "" -e "$(cat <<- EOF
    ${section_end}a\\
		[${args[section]}]
		EOF
    )" ${args[2]}

    # セクション最後尾に書き込み
    local target_row=$((${section_end} + 1))
    local sed_command="a"
  else
    # セクションがある場合は最後尾に追加
    local target_row=${section_end}
    local sed_command="i"
  fi

  # INIファイルに書き込み
  sed -i "" -e "$(cat <<- EOF
  ${target_row}${sed_command}\\
	${addition}
	EOF
  )" ${args[2]}
}

# AppleScriptでダイアログを表示する
# @param string $1 メッセージ
dialog() {
  osascript -l JavaScript -e "function run(arguments) {
    var app = Application('System Events');
    app.includeStandardAdditions = true;
    app.displayDialog(arguments[0]);
  }" "$1"
}

# AppleScriptで通知を表示する
# @param string $1 メッセージ
notify() {
  osascript -l JavaScript -e "function run(arguments) {
    var app = Application.currentApplication();
    app.includeStandardAdditions = true;
    app.displayNotification(arguments[0], { withTitle: 'Tool Script', soundName: 'Glass' });
  }" "$1"
}

# 仮想マシンのファイルを監視する
# @param string $1 ファイルパス
# @param string $2 オプション
watch_vm_file() {
  case $2 in
  '' ) local call='';;
  -c ) local call='| ccze -A' || local call='';;
  * )
    local call=''
    for word in ${@:2}; do
      if [[ "$word" =~ ^sed ]]; then
        local sed=`echo ${word} | sed -e 's/^sed //'`
        [ -e $is_sed ] && local call="${call} | sed -e '${sed}'" || local call="${call} -e '${sed}'"
        printf $TEXT_INFO_DARK "[SED] ${sed}"
        local is_sed=true
      else
        local call="${call} | grep --line-buffered '${word}'"
        printf $TEXT_INFO_DARK "[GREP] ${word}"
      fi
    done
    printf $TEXT_INFO_DARK $call
    ;;
  esac

  # / が含まれなければ自動的に/var/logを見る
  [[ $1 =~ '/' ]] && local log_file="$1" || local log_file="/var/log/$1"
  printf $TEXT_INFO "Start Watching '${log_file}'..."

  if [ "$VM_PLATFORM" = "vagrant" ]; then
    cd_vagrant
    vagrant ssh -c "tail -f ${log_file} ${call}"
  else
    docker compose exec web bash -c "tail -f ${log_file} ${call}"
  fi
}

# 環境毎のURLのホスト名とプロトコルを出力する
# @param string $1 環境名(未指定でローカル) [local,production,staging]
# @returns string ホスト名・プロトコル
project_origin() {
  case $1 in
  production|p ) echo $DOMAIN_PRODUCTION ;;
  staging|s ) echo $DOMAIN_STAGING ;;
  local|* )
    if [[ "$VM_PLATFORM" == "vagrant" ]]; then
      # Vagrant
      cd_vagrant
      [ "$VAGRANT_SSH_PROTOCOL" = "true" ] && local protocol='https' || local protocol='http'
      local hostname="$(grep '.vm.network :private_network, ip: "*"' ./Vagrantfile | grep -o '\d\+.\d\+.\d\+.\d\+')"
      if [ -z "$hostname" ]; then
        local hostname="$(grep '.vm.network \"private_network\", ip: \"*\"' ./Vagrantfile | grep -o '\d\+.\d\+.\d\+.\d\+')"
      fi
      echo "${protocol}://${hostname}"
    else
      # Docker
      local expose=443
      local port=$(docker ps -q --filter "expose=${expose}" | xargs docker inspect -f "{{ (index (index .NetworkSettings.Ports \"${expose}/tcp\") 0).HostPort }} {{ .HostConfig.Binds }}" | grep ${PROJECT_DIR} | sed 's/ .*//')

      echo "https://localhost:${port}"
    fi
  esac
}

# 直近の package.json が配置されているディレクトリパスを取得する
# @returns string package.json ディレクトリパス
# @throws $EXIT_CODE_ERROR
node_root() {
  local target_dir=$(pwd)
  while [ ! -f "${target_dir}/package.json" ]; do
    target_dir=$(dirname "${target_dir}")
    if [ "${target_dir}" = "/" ]; then
      printf $TEXT_DANGER "Package.json not found."
      exit $EXIT_CODE_ERROR &> /dev/null
    fi
  done
  echo "${target_dir}"
}

# Dockerコンテナの環境変数を取り出す
# 値やキーに空白を含む場合はevalを通す必要あり (zshの配列定義の仕様上、クオートを無視して区切られてしまう)
# @returns string 連想配列の中身
# @example eval "local -A docker_env=($(docker_container_env))"
docker_container_env() {
  local yaml_path="${PROJECT_DIR}/docker-compose.yaml"
  local -A environment=()

  # grep -n 'environment:' ${yaml_path}
  # grep -n 'environment:' ${yaml_path} |  tr -dc ' ' | wc -c

  local headings=($(grep -n 'environment:' ${yaml_path} | sed 's/:.*$//'))
  for heading in ${headings}; do
    local indentCount=$(($(head -n ${heading} ${yaml_path} | tail -n 1 | sed "s/^\( *\).*/\1/" | wc -c) - 1))
    # 行番号とインデント幅を取得
    local line_no=$(($(echo ${heading} | sed 's/:.*$//') + 1))
    local indent=$(head -n ${heading} ${yaml_path} | tail -n 1 | sed "s/^\( *\).*/\1/")

    IFS=$'\n'
    for item in $(tail -n +${line_no} ${yaml_path}); do
      IFS=$DEFAULT_IFS
      if [[ ${item} =~ "^${indent}  " ]]; then
        # environment項目内をスペース区切りで出力
        if [[ "${item}" == *=* ]]; then
          local pair=$(echo ${item} | sed "s/^[ -]*//" | sed "s/ *= */:/")
        else
          local pair=$(echo ${item} | sed "s/^[ -]*//" | sed "s/: /:/")
        fi
        echo ${pair%:*} ${pair#**:}
      else
        # インデントが解除されたら終了
        break
      fi
    done
  done
}

# カレントディレクトリのGithubのURLを出力する
# @returns string GithubのURL
github_url() {
  local remote_params=$(git remote -v 2> /dev/null | sed -n -e 1p)
  if [ -z "${remote_params}" ]; then
    echo "https://github.com"
  elif [[ ${remote_params} =~ '^origin.*https://' ]]; then
    echo ${remote_params} | grep -oe "https://.*\.git" | sed "s|\.git||"
  else
    echo "https://github.com/$(echo ${remote_params} | grep -oe "[a-zA-Z-]*/.*\.git" | sed "s|\.git||")"
  fi
}

# ブランチ番号からプルリクエストページを開く
open_git_pulls() {
  local url=$(github_url)
  local pathname="pulls?q=is%3Apr"
  if [ $# = 0 ]; then
    pathname+="+is%3Aopen"
  elif [ "$1" = "current" ]; then
    pathname="pull/$(git rev-parse --abbrev-ref HEAD)"
  elif [ $# = 1 ]; then
    pathname="pull/${BRANCH_PREFIX}$1"
  else
    for branch_num in $@; do
      pathname+="+head%3A${BRANCH_PREFIX}${branch_num}"
    done
  fi
  browser_open "${url}/${pathname}"
}

# 見出しを出力する
# @param string $1 見出し内容
print_heading() {
  local text="${@}"
  local padding=6
  local divider_char="─"
  local divider_length=$((${#text} + $padding * 2))

  printf "${COLOR_SUCCESS}${divider_char}%.s${COLOR_RESET}" {1..${divider_length}}
  echo ""
  printf " %.s${COLOR_RESET}" {1..${padding}}
  printf $TEXT_SUCCESS ${text}
  printf "${COLOR_SUCCESS}${divider_char}%.s${COLOR_RESET}" {1..${divider_length}}
  echo ""
}

# ヘルプメッセージを表示する
# @param string $1 対象ソースコード (未指定でスクリプトファイル全体)
# @option --action=<string> アクション名 (未指定ですべてのヘルプを表示)
# @example print_help $(cat example.sh) --action=example
#   ## [example_command] コマンド説明
#   ## --example-option=<example_value> オプション説明
#   ### [example_sub_command] サブコマンド説明
print_help() {
  parse_arguments ${@}; local -A args=(${(kv)ARGUMENTS_REPLY})

  local code=${args[1]}
  [ -z "${args[1]}" ] && code=$(cat $TOOL_SCRIPT)

  ## --action 特定アクションのヘルプのみ表示
  if [ -n "${args[action]}" ]; then
    code=$(echo ${code} | text_subtract "^\s*#\{2,\} \[${args[action]}.*\]" "^## \[")
  fi

  # コメント以外を削除
  local comments=$(echo ${code} | grep -a "^\s*#\{2,\}" | grep -v '^\s*## sh')

  echo ${comments} |
    sed -e "s/^ *#\{3,\} /  /g" | # インデントを調整してコメントアウトを削除
    sed -e "s/^ *## \([-\[]\)/\1/g" | # アクションとコメントのコメントアウトを削除
    sed -e "s/^ *## / /g" | # その他コメントアウトを削除してインデントを調整
    sed -e "s/^\( *-\{1,2\}[a-z][a-z-]*\)\(.*\)/  ${COLOR_NOTICE}\1\2${COLOR_RESET}/g" | # オプションを書式調整
    sed -e "s/\[\(.*\)\]/${COLOR_MUTED}to ${COLOR_RESET}${COLOR_WARNING}\1${COLOR_RESET}/g" # []を着色
}

# プロジェクト設定値のINI設定を入力する
# @param string $1 項目名
# @param string $2 デフォルト値
# @param string $3 引数を3つ以上指定した場合は選択肢として表示
# @returns $FUNCTION_REPLY 入力値
read_project_prop() {
  local prop=${1}
  local default=$(parse_ini ${PROJECTS_INI} --section=${PROJECT_NAME} --key=${prop})
  local default_section=$(parse_ini ${PROJECTS_INI} --section=default --key=${prop})

  if [ $# -le 2 ]; then
    # 引数が1〜2個の場合は文字列入力
    [ -z "${default}" ] && default=${2}

    [ -n "${default}" ] && local label="${COLOR_INFO_DARK}${1} (${default}):${COLOR_RESET} " || local label="${COLOR_INFO_DARK}${1}:${COLOR_RESET} "
    echo -n "${label}"
    local input
    read input
    input=$(echo $input | sed 's/ //')
    if [[ "$input" == "" ]]; then
      [ -n "$default" ] && echo "${PREV_LINE}${label}${default}" || echo "${PREV_LINE}${label}${COLOR_MUTED}skip${COLOR_RESET}"
      input=${default}
    fi
  else
    # 引数が3個以上の場合は選択肢入力
    [ -z "$default" ] && default=$(echo ${2} | sed 's/^\([^:]*\): *.*/\1/')
    echo "${COLOR_INFO_DARK}${prop} (${default}):${COLOR_RESET}"
    read_selection_long ${@:2} && local input=${FUNCTION_REPLY}
    [[ "${input}" == "none" ]] && input=""
  fi

  # 入力がないか変更がなければスキップ
  if [[ -z "${input}" || "${input}" == "${default}" ]]; then
    FUNCTION_REPLY=${default}
    return
  fi
  if [[ "${input}" == "${default_section}" ]]; then
    FUNCTION_REPLY=${default_section}
    return
  fi

  # INIファイルに書き込み
  [ $# -le 2 ] && local line="${prop}=\"${input}\"" || local line="${prop}=${input}"
  set_ini ${line} ${PROJECTS_INI} --section=${PROJECT_NAME}
  FUNCTION_REPLY=${input}
}


# デフォルト値ありの文字列入力
# @param string $1 項目名
# @param string $2 デフォルト値
# @returns $FUNCTION_REPLY 入力値
read_with_default() {
  [ -n "${2}" ] && local label="${COLOR_INFO_DARK}${1} (${2}):${COLOR_RESET} " || local label="${COLOR_INFO_DARK}${1}:${COLOR_RESET} "
  echo -n "${label}"
  local input
  read input
  input=$(echo $input | sed 's/ //')
  if [[ "$input" == "" ]]; then
    echo "${PREV_LINE}${label}${2}"
    FUNCTION_REPLY=${2}
    return
  fi
  FUNCTION_REPLY=${input}
}

# 選択表示
# @param string $@ 選択肢 (1つしかなければ選択肢を表示しない)
# @returns $FUNCTION_REPLY 選択した項目が格納される
# @example read_selection ls diff export import && local result=${FUNCTION_REPLY}
read_selection() {
  local items=(${@})
  local current_index=1

  if [ ${#items[@]} -le 1 ]; then
    local item=${items[1]}
    echo "${COLOR_SUCCESS}➣ ${item}${COLOR_RESET}"
    FUNCTION_REPLY=$(echo ${item} | sed 's/^\([^:]*\): .*/\1/' )
    return
  fi

  # 項目選択の表示更新
  render_selection() {
    echo -n "\r"
    local index=0
    for item in "${items[@]}"; do
      index=$((${index} + 1))
      if [[ $index == $current_index ]]; then
        echo -n "${COLOR_SUCCESS}➣ ${item}${COLOR_RESET}  "
      else
        echo -n "${COLOR_MUTED}  ${item}${COLOR_RESET}  "
      fi
    done
  }

  local keycode
  while ((render_selection) &) && IFS= read -r -k1 -s keycode && [[ -n "$keycode" ]]; do
    if [[ $keycode == $'\x1b' ]]; then
      read -r -k2 -s rest
      keycode+="$rest"
    fi
    case $keycode in
    $'\x1b\x5b\x44' | $'\x1b\x5b\x41' ) # Left or Up
      [ $current_index -gt 1 ] && current_index=$((current_index - 1)) || current_index=${#items[@]}
      ;;
    $'\x1b\x5b\x43' | $'\x1b\x5b\x42' ) # Right or Down
      [ ${current_index} -lt ${#items[@]} ] && current_index=$((current_index + 1)) || current_index=1
      ;;
    $'\x0a' | $'\x20' ) # Enter or Space
      echo ""
      local item=$items[${current_index}]
      FUNCTION_REPLY=$(echo ${item} | sed 's/^\([^:]*\): .*/\1/')
      break
      ;;
    esac
  done
}

# 選択表示 (縦)
# @param string $@ 選択肢 (1つしかなければ選択肢を表示しない タブ文字区切りで入力すると前方部分だけを返す)
# @returns $FUNCTION_REPLY 選択した項目が格納される
# @example read_selection_long "1\tone" "2\ttwo" "3\tthree" && local result=${FUNCTION_REPLY}
read_selection_long() {
  local items=(${@})
  local current_index=1
  local line_limit=$(($(stty size | awk '{print $2}') * 0.5))

  # 一度文字列に変換してから表示用に列を整形する
  local labels=()
  local text=''
  for item in "${@}"; do
    text="${text}$(echo ${item} | tr '\n' ' ' | sed 's/^\([^:]*\): \(.*\)/\1\t\2/')\n"
  done
  local list=$(echo ${text}| column -t -s $'\t')
  IFS=$'\n'
  for label in $(echo ${list}); do
    IFS=$DEFAULT_IFS
    labels+=($label)
  done

  # 項目が一つの場合は即時決定
  if [ ${#items[@]} -le 1 ]; then
    echo "${COLOR_SUCCESS}➣ ${labels[1]}${COLOR_RESET}"
    local item=${items[1]}
    FUNCTION_REPLY=$(echo ${item} | sed 's/\t.*$//')
    return
  fi

  # 項目選択の表示更新
  render_selection() {
    # カーソル位置を戻す
    printf "${PREV_LINE}%0.s" {1..${#labels[@]}}

    local label
    local index=0
    for label in "${labels[@]}"; do
      index=$((${index} + 1))
      if [[ $index == $current_index ]]; then
        echo "${COLOR_SUCCESS}➣ ${label:0:$line_limit}${COLOR_RESET}"
      else
        echo "${COLOR_MUTED}  ${label:0:$line_limit}${COLOR_RESET}"
      fi
    done
  }

  # カーソルの位置を下端に調整
  printf "\n%0.s" {1..${#labels[@]}}

  local keycode
  while ((render_selection) &) && IFS= read -r -k1 -s keycode && [[ -n "$keycode" ]]; do
    if [[ $keycode == $'\x1b' ]]; then
      read -r -k2 -s rest
      keycode+="$rest"
    fi
    case $keycode in
    $'\x1b\x5b\x44' | $'\x1b\x5b\x41' ) # Left or Up
      [ $current_index -gt 1 ] && current_index=$((current_index - 1)) || current_index=${#items[@]}
      ;;
    $'\x1b\x5b\x43' | $'\x1b\x5b\x42' ) # Right or Down
      [ ${current_index} -lt ${#items[@]} ] && current_index=$((current_index + 1)) || current_index=1
      ;;
    $'\x0a' | $'\x20' ) # Enter or Space
      echo ""
      local item=${items[${current_index}]}
      FUNCTION_REPLY=$(echo ${item} | sed 's/\t.*$//')
      break
      ;;
    esac
  done
}

# OK・Cancelの選択を受け付ける
# `set -e`が有効ならコマンド単体使用でOKでないときは中断
# @returns OKなら終了ステータス0、Cancelなら終了ステータス1
# @example read_confirmation || return 1
read_confirmation() {
# Prompts the user to select between "Cancel" and "OK".
# @returns 0 if "OK" is selected, 1 if "Cancel" is selected.

  read_selection Cancel OK
  local answer=${FUNCTION_REPLY}

  case $answer in
  OK ) return $EXIT_CODE_SUCCESS;;
  Cancel ) return $EXIT_CODE_ERROR;;
  esac
}

# 複数行の文字列入力を受け付ける
# @param string $1 表示メッセージ
# @option --file 存在するファイルパスのみ受け付ける
# @returns $FUNCTION_REPLY 入力値
read_multiline() {
  parse_arguments ${@}; local -A args=(${(kv)ARGUMENTS_REPLY})

  local input=""
  printf $TEXT_INFO "${args[1]} (^D or ⏎⏎ to finish)"

  local line
  while read line; do
    if [ -z "${line}" ]; then
      echo -n "${PREV_LINE}"
      break
    fi

    if [ -n "${args[file]}" ] && [ ! -f $line ]; then
      echo "${PREV_LINE}${line} ${COLOR_DANGER}[File not found.]${COLOR_RESET}"
      continue
    fi

    [ -n "${input}" ] && input+="\n${line}" || input+="${line}"
  done

  FUNCTION_REPLY=${input}
}

# 環境環境を選択する
# @param string 環境名 (入力があれば選択肢を出さない)
# @returns $FUNCTION_REPLY 環境名
read_environment() {
  if [ -n "$1" ]; then
    FUNCTION_REPLY=$(parse_environment $1)
  else
    local -a envs=("local")

    [ -n "$SSH_NAME_STAGING" ] || [ -n "$DOMAIN_STAGING" ] && envs+=("staging")
    [ -n "$SSH_NAME_PRODUCTION" ] || [ -n "$DOMAIN_PRODUCTION" ] && envs+=("production")
    read_selection $envs
  fi
}

# Gitのブランチを選択する
# @param string 環境名 (入力がなければ)
# @returns $FUNCTION_REPLY 環境名
read_git_branch() {
  local main=$(git branch --format='%(refname:short)' | grep -e '^master$' -e '^main$')
  local option=""
  [ -n "$(git branch --list ${BASE_BRANCH})" ] && option="--no-merged=${BASE_BRANCH}"

  IFS=$'\n'
  local -a branches=(${BASE_BRANCH} ${main} $(git branch --format="%(refname:short)	%(subject)" --sort=-authordate ${option} | head -10 ))
  IFS=$DEFAULT_IFS
  read_selection_long $branches
}

# JXA内でタブを取得するJavaScriptを出力する (プロセス内でタブが開かれていなければ現在のタブ)
# @param string $1 Safariオブジェクトの変数名
# @example
#   const safari = Application('Safari');
#   const tab = $(browser_script_current_tab safari);
browser_script_current_tab() {
  local safari=$1
  local window_id=${BROWSER_CURRENT_TAB_ID%:*}
  local tab_index=${BROWSER_CURRENT_TAB_ID#*:}
  echo "
  (() => {
    const window = ('${window_id}' ? ${safari}.windows.whose({ id: '${window_id}' }).at(0) : undefined) ?? ${safari}.windows.at(0);
    return ('${tab_index}' ? window.tabs.at(${tab_index} - 1) : undefined) ?? window.currentTab;
  })()
  "
}

# ブラウザでURLを開く
# 開いているタブのドメインが同じ場合はそのまま遷移し
# 違うドメインの場合は次のDOM操作に影響しないよう表示中ページの内容を削除してから遷移を始める
# @param string $1 URL
# @option --quiet 標準出力をしない
# @option --sync URLが開かれるのを待つ
# @option --background フォーカスしない
# @option --alt 別のブラウザで開く
# @option --newtab 強制的に新しいタブを開く(未設定で前回と同じタブを操作する)
# @option --skip 同じURLの場合はスキップ
browser_open() {
  parse_arguments ${@}; local -A args=(${(kv)ARGUMENTS_REPLY})
  [ -z "${args[quiet]}" ] && printf $TEXT_INFO_DARK "Browser: ${args[1]}"
  [ -n "${args[newtab]}" ] && local tab_id=${BROWSER_CURRENT_TAB_ID} || local tab_id=""
  [ -n "${args[skip]}" ] && local is_skip_enabled="true" || local is_skip_enabled=""

  if [ -n "${args[alt]}" ]; then
    open -a "Google Chrome" ${args[1]}
  else
    local timeout=0
    [ -n "${args[sync]}" ] && local timeout=10

    local res=$(osascript -l JavaScript -e "function run([url, timeout, tabId = '', isSkipEnabled = false]) {
      const [windowId, tabIndex] = tabId.split(':', 2);
      const safari = Application('Safari');
      if (!safari.windows.length) safari.Document().make();

      const window = (windowId ? safari.windows.whose({ id: windowId }).at(0) : undefined) ?? safari.windows.at(0);
      let tab = (tabIndex ? window.tabs.at(tabIndex) : undefined) ?? window.currentTab;
      const isSkip = isSkipEnabled && tab.url().toString().replace(/\/\$/, '') === url.replace(/\/\$/, '');

      const prevUrl = tab.url();
      if (tabIndex === undefined && !prevUrl?.startsWith('favorites://') && !url.startsWith(prevUrl?.replace(/^(\w+:\/\/[^\/]+).*/, '\$1'))) {
        tab = safari.Tab();
        window.tabs.push(tab);
        tab.url = url;
      } else {
        const isSkip = isSkipEnabled && tab.url().toString().replace(/\/\$/, '') === url.replace(/\/\$/, '');
        if (!isSkip) {
          safari.doJavaScript(rst = 'document.body.innerHTML = \'\';', { in: tab });
          tab.url = url;
        }
      }

      const res = window.id() + ':' + tab.index();

      if (!Number(timeout)) return res;
      for (let i = 0; i < timeout; i += 1) {
        if (i > 0) delay(1);
        const isReady = safari.doJavaScript(result = 'document.body.innerText && (document.readyState === \'complete\')', { in: tab });
        if (isReady) return res;
      }
      return '';
    }" ${args[1]} ${timeout} "${tab_id}" ${is_skip_enabled})

    [ -z "${res}" ] && exit $EXIT_CODE_TIMEOUT
    BROWSER_CURRENT_TAB_ID=${res}

    if [ -z "${args[background]}" ]; then
      browser_focus
    fi
  fi
}

# ブラウザで特定のURLが開かれるのを待つ
# @param string $1 URL
browser_wait() {
  parse_arguments ${@}; local -A args=(${(kv)ARGUMENTS_REPLY})
  printf $TEXT_INFO "Wait for ${args[1]}"

  osascript -l JavaScript -e "function run(arguments) {
    const safari = Application('Safari');
    const tab = $(browser_script_current_tab safari);

    for (let i = 0; i < 10; i += 1) {
      if (i > 0) delay(1);
      const ret = safari.doJavaScript(result = 'location.href', { in: tab });
      if (ret === arguments[0]) return true;
    }
    return null;
  }" ${args[1]} &> /dev/null
}

# ブラウザを前面に表示する
# @option --fixed-tab 強制的に現在のタブを参照する
browser_focus() {
  [ "$1" = "--fixed-tab" ] && local fixed_tab=true || local fixed_tab=false
  osascript -l JavaScript -e "function run([fixedTab]) {
    const safari = Application('Safari');
    safari.activate();

    if (fixedTab) {
      const tab = $(browser_script_current_tab safari);
      safari.windows.at(0).currentTab = tab;
    }
  }" "${fixed_tab}" &> /dev/null
}


# ブラウザのタブを閉じる
browser_close() {
  osascript -l JavaScript -e "function run([fixedTab]) {
    const safari = Application('Safari');
    const tab = $(browser_script_current_tab safari);
    tab.close();
  }" &> /dev/null
}

# SafariのアクティブなタブでJavaScriptを即時実行する
# @param string $1 JavaScriptコード
browser_javascript() {
  osascript -l JavaScript -e "function run([script, ...arguments]) {
    const safari = Application('Safari');
    const tab = $(browser_script_current_tab safari);
    return safari.doJavaScript(result = '(() => { const arguments = ' + JSON.stringify(arguments) + '; ' + script + ' })()', { in: tab });
  }" $@
}

# SafariのアクティブなタブでJavaScriptを実行し、戻り値があるまで待機する
# @param string $1 JavaScriptコード (returnで文字列を返すようにする)
browser_javascript_sync() {
  osascript -l JavaScript -e "function run([script, ...arguments]) {
    const safari = Application('Safari');
    const tab = $(browser_script_current_tab safari);

    for (let i = 0; i < 10; i += 1) {
      if (i > 0) delay(1);
      const ret = safari.doJavaScript(result = '(() => { const arguments = ' + JSON.stringify(arguments) + '; ' + script + ' })()', { in: tab });
      if (ret) return ret;
    }
    return '';
  }" $@
}

# SafariのアクティブなタブでJavaScriptを実行し、戻り値があるまで待機する
# @param string $1 JavaScriptコード (returnで文字列を返すようにする)
browser_javascript_sync_background() {
  osascript -l JavaScript -e "function run([script, ...arguments]) {
    const safari = Application('Safari');
    const tab = $(browser_script_current_tab safari);

    for (let i = 0; i < 10; i += 1) {
      if (i > 0) delay(1);
      const ret = safari.doJavaScript(result = '(() => { const arguments = ' + JSON.stringify(arguments) + '; ' + script + ' })()', { in: tab });

      if (ret) return ret;
    }
    return '';
  }" $@
}

# ブラウザでフォームを送信してページが切り替わるまで待つ
browser_submit() {
  printf $TEXT_INFO_DARK 'Browser: document.forms[0] - submit'
  local is_success=$(osascript -l JavaScript -e "function run(arguments) {
    const safari = Application('Safari');
    const tab = $(browser_script_current_tab safari);

    let url, prevHistoryLength = 0;
    for (let i = 0; i < 10; i += 1) {
      if (i > 0) delay(1);
      prevHistoryLength = safari.doJavaScript(result = 'history.length', { in: tab });
      url = safari.doJavaScript(result = '(() => { const form = document.forms[0]; if (form) { HTMLFormElement.prototype[\'submit\'].call(form); return location.href; } })()', { in: tab });
      if (url) break;
    }

    for (let i = 0; i < 10; i += 1) {
      if (i > 0) delay(1);
      const historyLength = safari.doJavaScript(result = 'history.length', { in: tab });
      if (historyLength !== prevHistoryLength) return true;
    }
    return '';
  }")
  if [ -z "${is_success}" ]; then
    exit $EXIT_CODE_TIMEOUT &> /dev/null
  fi
}

# セレクタからDOM要素を検索してテキストを取得
# @param string $1 CSSセレクタ
# @returns string DOM要素内のテキスト
browser_inner_text() {
  browser_javascript_sync "return document.querySelector('$1')?.innerText;"
}

# 特定のDOM要素の登場を待ってアクセスする
# 第二引数を省略した場合は登場を待つ
# @param string $1 セレクタ
# @param string $2 JavaScript (`element`変数で指定したDOM要素にアクセス)
browser_javascript_element() {
  sleep 0.01
  printf $TEXT_INFO_DARK "Browser: $1 $(echo ${2:0:20} | sed 's/^element\.//' | sed 's/;$//')"
  local is_success=$(browser_javascript_sync "const element = document.querySelector('$1'); if (element) { $2; return true; }")
  if [ -z "${is_success}" ]; then
    exit $EXIT_CODE_TIMEOUT &> /dev/null
  fi
}

# ブラウザでセレクタに文字列を入力
# @param string $1 セレクタ
# @param string $2 入力値
browser_set_input() {
  sleep 0.01
  printf $TEXT_INFO_DARK "Browser: $1 << $2"

  local script=$(cat <<- 'EOS'
    const [selector, value = ''] = arguments;
    const input = document.querySelector(selector);

    switch (input?.type) {
      case undefined:
        return '';
      case 'checkbox':
        input.checked = input.value === value;
        break;
      case 'radio':
        input.form[input.name].value = value;
        break;
      default:
        input.value = value.replace(/\\n/g, '\n');
    }
    return true;
	EOS
  )

  local is_success=$(browser_javascript_sync ${script} $@)
  if [ -z "${is_success}" ]; then
    exit $EXIT_CODE_TIMEOUT &> /dev/null
  fi
}

# 特定の文字列以降を取得する
# @param string $1 開始文字列
# @param string $2 対象文字列
# @returns 特定の文字列以降の文字列
# @example echo "one\ntwo\nthree" | text_after 'two'
text_after() {
  local text
  if [ -p /dev/stdin ]; then
      [ "$(echo ${@:2})" = "" ] && text=`cat -` || text=${@:2}
  else
      text=${@:2}
  fi

  local line=$(echo ${text} | grep -an -m1 $1 | head -1 | sed 's/:.*$//')
  if [ -n "$line" ]; then
    echo ${text} | tail -n +${line}
  fi
}

# 特定の文字列を切り出す
# 条件はGrepの形式のため、一部記号はバックスラッシュによるエスケープが必要
# @param string $1 開始行の条件 (開始行は含む)
# @param string $2 終了行の条件 (開始行移行で一致した行で終了 / 終了行は含まない)
# @param string $3 対象文字列
# @returns 特定の文字列以降の文字列
# @example echo "one\ntwo\nthree\nfour" | text_subtract 'two' 'three'
text_subtract() {
  local text
  if [ -p /dev/stdin ]; then
      [ "$(echo ${@:3})" = "" ] && text=`cat -` || text=${@:3}
  else
      text=${@:3}
  fi

  # $1で前方削除
  local start_row=$(echo ${text} | grep -an -m1 $1 | head -1 | sed 's/:.*$//')
  if [ -z "${start_row}" ]; then
    # printf $TEXT_DANGER "Start line not found in text_subtract. (start: $1 end: $2)"
    # exit $EXIT_CODE_WRONG_ARGUMENT &> /dev/null
    return
  fi
  text=$(echo ${text} | tail -n +${start_row})

  # $2で後方削除
  local end_row=$(echo ${text} | tail -n +2 | grep -an -m2 $2 | head -1 | sed 's/:.*$//')
  if [ -z "${end_row}" ]; then
    # printf $TEXT_DANGER "End line not found in text_subtract. (start: $1 end: $2)"
    # exit $EXIT_CODE_WRONG_ARGUMENT &> /dev/null
    return
  fi
  echo ${text} | head -n $(( ${end_row} - 1 ))
}

# 関数をすべて削除
unset_functions() {
  unset -f $(cat $FUNCTIONS_PATH | grep -E '^ *[a-zA-Z_]+\(\) \{' | sed -e 's|^\(.*\)() {.*|\1|' | xargs -L 1)
}

# 小数点以下の桁数を指定して割り算する
# @param number $1
# @param number $2 (以降すべての引数を割り算する)
# @option --digits=<number> 小数点以下の桁数
# @returns 計算結果を出力
math_division() {
  local -a numbers=()
  local digits=5
  for argument in ${@}; do
    case $argument in
    -d=[0-9]* | -digits=[0-9]* | --digits=[0-9]* )
      # 小数点桁数
      digits=${argument##*=}
      ;;
    [0-9]* )
      numbers+=("${argument}")
      ;;
    esac
  done

  local number=$((${numbers[1]} * 10 ** ${digits}))
  for divisor in ${numbers:1}; do
    number=$((${number} / ${divisor}))
  done

  echo $(printf "%.$((${digits}))f" $((number * 0.1 ** ${digits} )) | sed 's/[0\.]*$//')
}

# ランダムな数値を取得する
# @param number $1 最小値 (引数が1個の場合は最大値とする)
# @param number $2 最大値
# @example echo $(math_random 1 12)
math_random() {
  if [ $# -gt 1 ]; then
    local min=$1
    local max=$2
  else
    local min=0
    local max=$1
  fi
  if [ $max -lt $min ]; then
    exit $EXIT_CODE_WRONG_ARGUMENT &> /dev/null
  fi

  if type 'osascript' > /dev/null 2>&1; then
    osascript -l JavaScript -e "function run([min, max]) { return Math.floor(Math.random() * (max - min + 1) + Number(min)); }" $min $max
  else
    local diff=$(( $max - $min ))
    if [ $diff -gt 32767 ]; then
      exit $EXIT_CODE_WRONG_ARGUMENT &> /dev/null
    fi

    # 確率を均一にするために最大値を設定 (除算の時点で小数点以下が切り捨てられる)
    local limit=$(( 32767 / $diff * $diff ))
    while true; do
      local random=${RANDOM}
      if [ $random -lt $limit ]; then
        echo $(( $random % $diff + $min ))
        return
      fi
    done
  fi
}

# 配列を文字列に結合
# @param string $1 区切り文字
# @param string $2... 結合する配列
# @returns string 結合後の文字列
# @example array_join ',' array "${list[@]}"
array_join() {
  local is_first=true
  while read line; do
    ${is_first} && echo -n "${line}" || echo -n "${1}${line}"
    is_first=false
  done < <(echo "${@:2}")
}

array_split() {
  IFS=$'\n'
  local -a branches=(${BASE_BRANCH} ${main} $(git branch --format="%(refname:short)	%(subject)" --sort=-authordate ${option} | column -t -s $'\t' | head -10 ))
  IFS=$DEFAULT_IFS
}

# 文字列の行数を取得
# @returns int 行数
# @example $(echo ${text} | line_count)
line_count() {
  wc -l | sed -e 's/ //g'
}

# 指定されたパスの下にあるファイルに指定された拡張子が存在するかどうかを確認
# @param string $1 検索するパス
# @param string $2... 検索する拡張子
# @returns string 1件でも見つかった拡張子
# @example existing_file_extension . md txt
existing_file_extension() {
  for pattern in "${@:2}"; do
    local match=$(find $1 -type f -name "*.${pattern} | wc -l")
    if [ ${match} -ge 0 ]; then
      echo "${pattern}"
      return
    fi
  done
}