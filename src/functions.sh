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
# zshの連想配列の使用上、受け取り項目が分割されてしまうため、複数行やスペースを含む引数には対応していません
# evalを使用すると受け取ることができます
# @param string $@ 全引数
# @returns (string=string) 数字のキーに引数、文字列のキーにオプション
# @example
#   local -A args=($(parse_arguments ${@}))
#   eval "local -A args=($(parse_arguments ${@}))"
parse_arguments() {
  local index=1
  local -A options=()
  for i in $(seq $#); do
    local argument=${${@}[$i]}
    case $argument in
    - )
      # 引数
      options[$((index++))]=${argument}
      ;;
    -[0-9]=* | -[0-9][0-9]=* | --[0-9]=* | --[0-9][0-9]=* )
      # 数値キーのオプションはインデックスを上書きしないようにハイフンを削除しない
      local option_text="${argument}"
      [[ ${option_text} == *=* ]] && options[${option_text%=*}]=${option_text#*=} || options[${option_text}]=1
      ;;
    --*)
      # オプション
      local option_text=${argument#--}
      [[ ${option_text} == *=* ]] && options[${option_text%=*}]=${option_text#*=} || options[${option_text}]=1
      ;;
    -* )
      # オプション
      local option_text=${argument#-}
      [[ ${option_text} == *=* ]] && options[${option_text%=*}]=${option_text#*=} || options[${option_text}]=1
      ;;
    '' )
      ;;
    * )
      # 引数
      options[$((index++))]=${argument}
      ;;
    esac
  done

  # zsh対応の連想配列に変換
  for key in "${(k)options[@]}"; do
    echo "${hash_text}\n${key} ${options[${key}]}"
  done
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
  local -A args=($(parse_arguments ${@}))

  # ファイル名未指定では読み込みしない
  if [ -z "${args[1]}" ]; then
    return
  fi

  # 対象項目を取得
  if [ -n "${args[section]}" ]; then
    # Section constants
    local attributes=$(grep_after "\[${args[section]}\]" ${args[1]} | sed -e '1d' | sed -n '/^\[.*\]$/q;p')
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
# @example
set_ini() {
  local -A args=($(parse_arguments ${@}))

  # セクションの終わりの行を特定する
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

  # 次のセクションが見つからなければファイル末尾に書き込み
  if [[ ${section_end} == 0 ]]; then
    section_end=$(cat ${args[2]} | wc -l | sed -e 's/ //g')
  fi

  # 空白行を無視
  while [ -z "$(cat ${args[2]} | sed -n $((section_end - 1))P)" ]; do
    cat ${args[2]} | sed -n $((section_end - 1))P
    section_end=$((section_end - 1))
  done

  local section_text=$(sed -n $((section_start + 1)),${section_end}p ${args[2]})
  local duplicate_offset=$(echo ${section_text} | awk '{print $0}' | grep -n "^yokohama_spo_v_dev *= *" | head -1 | sed "s/^\([0-9]\{1,\}\).*$/\1/")
  if [ ${duplicate_offset} ]; then
    # すでにキーがある場合は行を上書き
    local target_row=$((duplicate_offset + section_start))
    sed -i "" -e "$(cat <<- EOF
    ${target_row}c\\
		$1
		EOF
    )" ${args[2]}
  else
    # セクション最後尾に書き込み
    sed -i "" -e "$(cat <<- EOF
    ${section_end}i\\
		$1
		EOF
    )" ${args[2]}
  fi
}

# ブラウザでキー入力する
# @param string $1 入力するキー
# @see キーコード一覧 https://eastmanreference.com/complete-list-of-applescript-key-codes
# @example browser_keydown "return"
browser_keydown() {
  osascript -e "tell application \"${BROWSER}\" to activate" -e "tell application \"System Events\" to keystroke $1"
}

# SafariのアクティブなタブでJavaScriptを即時実行する
# @param string $1 JavaScriptコード
browser_javascript() {
  osascript -l JavaScript -e "function run(arguments) {
    const safari = Application('Safari');
    return safari.doJavaScript(result = '(() => { ' + arguments[0] + ' })()', { in: safari.windows.at(0).currentTab });
  }" $1
}

# SafariのアクティブなタブでJavaScriptを実行し、戻り値があるまで待機する
# @param string $1 JavaScriptコード (returnで文字列を返すようにする)
browser_javascript_await() {
  osascript -l JavaScript -e "function run(arguments) {
    const safari = Application('Safari');

    for (let i = 0; i < 10; i += 1) {
      if (i > 0) delay(1);
      const safari = Application('Safari');
      const ret = safari.doJavaScript(result = '(() => { ' + arguments[0] + ' })()', { in: safari.windows.at(0).currentTab });
      if (ret) return ret;
    }
    return null;
  }" $1
}


# ブラウザで文字列を入力する (マルチバイト非対応)
# @param string $1 入力するキー
# @example browser_input "password"
browser_input() {
  browser_keydown "\"$1\""
}

# ブラウザで文字列を入力する
# @param string $1 入力値
# @param integer $2 タブ回数
browser_input_new() {
  if [ -n "$2" ]; then
    for i in {1..$2}; do
      browser_keydown 'tab'
    done
  fi

  sleep 1
  echo $1 | pbcopy
  browser_keydown '"a" using {command down}'
  browser_keydown '"v" using {command down}'
}

# セレクタからDOM要素を検索してテキストを取得
# @param string $1 CSSセレクタ
browser_inner_text() {
  browser_javascript_await "return document.querySelector('$1')?.innerText;"
}

# ブラウザでセレクタに文字列を入力
# @param string $1 セレクタ
# @param string $2 入力値
browser_input_value() {
  sleep 0.01
  browser_javascript_await "const element = document.querySelector('$1'); if (element) { element.value = '$2'; return true; }" &> /dev/null
}

## AppleScriptでダイアログを表示する
dialog() {
  local script=$(cat <<- 'EOS'
  function run(arguments) {
    var app = Application('System Events');
    app.includeStandardAdditions = true;
    app.displayDialog(args[0]);
  }
	EOS
  )
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
  cd "$(get_project_root)/vagrant/" &> /dev/null
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

# ブラウザでURLを開く
# @param string $1 URL
# @option --alt 別のブラウザで開く
open_in_browser() {
  local -A args=($(parse_arguments ${@}))

  if [[ -n "${args[alt]}" ]]; then
    local browser=$BROWSER_ALT
  else
    local browser=$BROWSER
  fi

  printf $TEXT_INFO "Open the website in browser. ${args[1]}"
  open -a $browser ${args[1]}
}

# カレントディレクトリのGithubのURLを出力する
# @returns string GithubのURL
github_url() {
  local remote_params=$(git remote -v 2> /dev/null | sed -n -e 1p)
  if [ -z "$remote_params" ]; then
    echo "https://github.com"
  elif [[ $remote_params =~ '^origin.*https://' ]]; then
    echo $remote_params | grep -oe "https://.*\.git" | sed "s|\.git|/${query}|"
  else
    echo "https://github.com/$(echo $remote_params | grep -oe "[a-zA-Z-]*/.*\.git" | sed "s|\.git|/${query}|")"
  fi
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
# @param string $1 アクション名 (未指定ですべてのヘルプを表示)
print_help() {
  if [ -n "$1" ]; then
    # 特定アクションのコメント (次のコマンドまでの間のコメントを抽出)
    local code=$(grep_after "^\s*#\{2,\} \[${1}.*\]" $TOOL_SCRIPT)
    local message="$(echo $code | head -n 1)\n$(echo -E $code | tail -n +2 | grep '^\s*##'| sed -n '/^## \[/q;p' )"
  else
    # 全ヘルプコメント
    local message=$(cat $TOOL_SCRIPT | grep "^\s*#\{2,\}" | grep -v '^\s*## sh')
  fi

  print_heading "Personal Tool Script"
  echo $message |
    sed -e "s/^ *#\{3,\} /  /g" | # インデントを調整してコメントアウトを削除
    sed -e "s/^ *## \([-\[]\)/\1/g" | # アクションとコメントのコメントアウトを削除
    sed -e "s/^ *## / /g" | # その他コメントアウトを削除してインデントを調整
    sed -e "s/^\( *-\{1,2\}[a-z][a-z-]*\)\(.*\)/  ${COLOR_NOTICE}\1\2${COLOR_RESET}/g" | # オプションを書式調整
    sed -e "s/\[\(.*\)\]/${COLOR_MUTED}to ${COLOR_RESET}${COLOR_WARNING}\1${COLOR_RESET}/g" # []を着色
}

# デフォルト値ありの文字列入力
# @param string デフォルト値
read_with_default() {
  local input2
  read input2
  input=$(echo $input2 | sed 's/ //')
  echo "[[$input]]"
  if [[ "$input" == "" ]]; then
    echo "${PREV_LINE}$1"
    FUNCTION_REPLY=$1
    return
  fi
  FUNCTION_REPLY=input
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
# @param string $@ 選択肢 (1つしかなければ選択肢を表示しない `: `区切りで入力すると前方部分だけを返す)
# @returns $FUNCTION_REPLY 選択した項目が格納される
# @example read_selection_long "1: one" "2: two" "3: three" && local result=${FUNCTION_REPLY}
read_selection_long() {
  local items=(${@})
  local current_index=1
  local line_limit=$(($(stty size | awk '{print $2}') * 0.5))

  if [ ${#items[@]} -le 1 ]; then
    echo "${COLOR_SUCCESS}➣ ${items[1]}${COLOR_RESET}"
    local item=${items[1]}
    FUNCTION_REPLY=$(echo ${item} | sed 's/^\([^:]*\): .*/\1/' )
    return
  fi

  # 項目選択の表示更新
  render_selection() {
    # カーソル位置を戻す
    for item in "${items[@]}"; do
      echo -n "${PREV_LINE}"
    done

    local item
    local index=0
    for item in "${items[@]}"; do
      index=$((${index} + 1))
      if [[ $index == $current_index ]]; then
        echo "${COLOR_SUCCESS}➣ ${item:0:$line_limit}${COLOR_RESET}"
      else
        echo "${COLOR_MUTED}  ${item:0:$line_limit}${COLOR_RESET}"
      fi
    done
  }

  # カーソルの位置を下端に調整
  for item in "${items[@]}"; do
    echo ""
  done

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
      FUNCTION_REPLY=$(echo ${item} | sed 's/^\([^:]*\): .*/\1/' )
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
  read_selection Cancel OK
  local answer=${FUNCTION_REPLY}

  case $answer in
  OK ) return $EXIT_CODE_SUCCESS;;
  Cancel ) return $EXIT_CODE_ERROR;;
  esac
}

# 環境環境を選択する
# @param string 環境名 (入力がなければ)
# @returns $FUNCTION_REPLY 環境名
read_environment() {
  if [ -n "$1" ]; then
    FUNCTION_REPLY=$(parse_environment $1)
  else
    local -a envs=("local")
    [ -n "$SSH_NAME_STAGING" ] && envs+=("staging")
    [ -n "$SSH_NAME_PRODUCTION" ] && envs+=("production")
    read_selection $envs
  fi
}

# Gitのブランチを選択する
# @param string 環境名 (入力がなければ)
# @returns $FUNCTION_REPLY 環境名
read_git_branch() {
  local option=""
  [ -n "$(git branch --list ${BASE_BRANCH})" ] && option="--no-merged=${BASE_BRANCH}"

  IFS=$'\n'
  local -a branches=($(git branch --format="%(refname:short): %(subject)" --sort=-authordate ${option} | head -10 ))
  IFS=$DEFAULT_IFS

  read_selection_long $branches
}

# 特定の文字列以降を取得する
# @param string $1 開始文字列
# @param string $2 ファイル名
# @returns 特定の文字列以降のファイル内容
grep_after() {
  local line=$(cat $2 | grep -n -m1 $1 | head -1 | sed 's/:.*$//')
  if [ -n "$line" ]; then
    tail -n +${line} $2
  fi
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
