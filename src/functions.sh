# スクリプト関数ファイル
# 汎用定数が読み込まれている前提の関数あり

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
# @param string $@ 全引数
# @returns (string=string) 数字のキーに引数、文字列のキーにオプション
# @example local -A args=($(parse_arguments ${@}))
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

# オプションを除外した引数を読み取る
# @param string $@ 全引数
parse_arguments_array() {
  local -a args=()
  for i in $(seq $#); do
    local arg=${${@}[$i]}
    case $arg in
      - )
        # 配列一つ目の要素がハイフンだと無視されるため対処
        [[ $i == 1 ]] && args+='- -' || args+='-'
        ;;
      --*|-*) ;;
      * ) args+=${arg} ;;
    esac
  done
  echo ${args}
}

# オプションを読み取る
# @param string $@ 全引数
parse_options() {
  local -A options=()
  for i in $(seq $#); do
    local arg=${${@}[$i]}
    case $arg in
      - )
        ;;
      --*)
        local option_text=${arg#--}
        [[ ${option_text} == *=* ]] && options[${option_text%=*}]=${option_text#*=} || options[${option_text}]=1
        ;;
      -* )
        local option_text=${arg#-}
        [[ ${option_text} == *=* ]] && options[${option_text%=*}]=${option_text#*=} || options[${option_text}]=1
        ;;
    esac
  done

  local hash_text=''
  for key in "${(k)options[@]}"; do
    local hash_text="${hash_text}\n${key} ${options[${key}]}"
  done
  echo -e $hash_text
}

# プロジェクトルートパスを取得 (Workspace直下か.gitのあるディレクトリをルートとする)
get_project_root() {
  local current_dir=$(pwd)
  local project_name=$(echo ${current_dir} | sed -e "s|${WORKSPACE}/\([^/]*\).*$|\1|")

  if [[ "$project_name" != $(basename ${current_dir}) ]] && [ -e ".git" ]; then
    echo ${current_dir}
  else
    echo "${WORKSPACE}/${project_name}"
  fi
}

# INIファイルから項目を取得
# @param string $1 INIファイルパス
# @option --section=<string> 対象とするセクション名 (未指定の場合は全項目)
# @option --key=<string> 特定の項の値を出力する
# @returns string 変数宣言コード
# @example source <(parse_ini ./example.ini $2 | sed "s/^ */local /g")
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
    echo ${attributes} | grep "^${args[key]} *=" | head -1 | sed "s/^${args[key]} *= *//"
  else
    # 空白行を除外・イコール周辺のスペース削除して項目行を出力
    echo ${attributes} | sed '/^$/d' | sed 's/ *= */=/g'
  fi
}

# @param string $1 追記内容
# @param string $2 INIファイルパス
# @option --section=<string> 対象とするセクション名 (未指定の場合は全項目)
set_ini() {
  local -A args=($(parse_arguments ${@}))
  local lines=$(cat ${args[2]} | grep -n "\[.*\]")

  local target=0

  # TODO: grep_after -> grep に変更する
  if [ -n "$args{1}" ]; then
    local is_matched=false
    while read line; do
      if "${is_matched}"; then
        local target=${line%%:*}
        break
      fi

      local section=$(echo ${line#*:} | sed "s/^\[\(.*\)\]$/\1/")
      if [[ "${section}" == "$args[section]" ]]; then
        local is_matched=true
      fi
    done <<< "${lines}"
  fi

  if [[ target > 0 ]]; then
    sed -i "" -e "$(cat <<- EOF
    ${target}i\\
		${args[1]}
		EOF
    )" ${args[2]}
  else
    echo ${args[1]} >> ${args[2]}
  fi
}

# ブラウザでキー入力する
# @param string $1 入力するキー
# @see キーコード一覧 https://eastmanreference.com/complete-list-of-applescript-key-codes
# @example browser_keydown "return"
browser_keydown() {
  osascript -e "tell application \"${BROWSER}\" to activate" -e "tell application \"System Events\" to keystroke $1"
}

# ブラウザで文字列を入力する
# @param string $1 入力するキー
# @example browser_input "password"
browser_input() {
  browser_keydown "\"$1\""
}

# @param string $1 CSSセレクタ
# @param string $2 入力値
browser_input_new() {
  browser_javascript $(cat <<- 'EOS'
    console.info('Apple Event', document.forms[0].login_id.value);
    document.querySelector(arguments[0]).focus();
    document.querySelector(arguments[0]).select();
	EOS
  )

  # browser_input $2
}

browser_javascript() {
  osascript -l JavaScript -e "function run(arguments) {
    const safari = Application('Safari');
    safari.doJavaScript(arguments[0], { in: safari.windows.at(0).currentTab });
  }" $1
}

browser_selector_input() {
  for i in {1..10}; do
    browser_keydown 'tab'
  done

  browser_keydown 'tab'
  browser_keydown 'tab'

  browser_javascript $(cat <<- EOS
    console.log(document.querySelector('${1}'));
    document.querySelector('${1}').focus();
    document.querySelector('${1}').select();
	EOS
  )
  sleep 2

  echo $2 | pbcopy
  browser_keydown '"a" using {command down}'
  browser_keydown '"v" using {command down}'
  sleep 1
  browser_javascript $(cat <<- EOS
    document.activeElement.blur();
	EOS
  )
  sleep 1
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
  cd "${VAGRANT_DIR}" &> /dev/null
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
      [ "$VAGRANT_SSH_PROTOCOL" = "true" ] && local protocol='https' || local protocol='http'
      local hostname="$(grep '.vm.network :private_network, ip: "*"' ${VAGRANT_DIR}Vagrantfile | grep -o '\d\+.\d\+.\d\+.\d\+')"
      if [ -z "$hostname" ]; then
        local hostname="$(grep '.vm.network \"private_network\", ip: \"*\"' ${VAGRANT_DIR}Vagrantfile | grep -o '\d\+.\d\+.\d\+.\d\+')"
      fi
      echo "${protocol}://${hostname}"
    else
      # Docker
      local expose=443
      local port=$(docker ps -alq --filter "expose=${expose}" | xargs docker inspect -f "{{ (index (index .NetworkSettings.Ports \"${expose}/tcp\") 0).HostPort }} {{ .HostConfig.Binds }}" | grep ${PROJECT_DIR} | sed 's/ .*//')

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
  local lines=($(grep -n 'environment:' ${yaml_path} | sed 's/:.*$//'))
  for line in ${lines}; do
    local line=$(( line + 1 ))
    tail -n +${line} ${yaml_path} | while read item; do
      if [[ "${item}" == "- "*=* ]]; then
        local pair=${item:2}
        echo ${pair%=*} ${pair#**=}
      else
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

# ヘルプメッセージを表示する
# @param string $1 アクション名 (未指定ですべてのヘルプを表示)
print_help() {
  if [ -n "$1" ]; then
    # 特定アクションのコメント (次のコマンドまでの間のコメントを抽出)
    local code=$(grep_after "^\s*#\{2,\} \[${1}.*\]" $TOOL_SCRIPT)
    local message="$(echo $code | head -n 1)\n$(echo $code | tail -n +2 | grep '^\s*##'| sed -n '/^## \[/q;p' )"
  else
    # 全ヘルプコメント
    local message=$(cat $TOOL_SCRIPT | grep "^\s*#\{2,\}" | grep -v '^\s*## sh')
  fi

  printf $TEXT_SUCCESS "──────────────────────"
  printf $TEXT_SUCCESS " Personal Tool Script "
  printf $TEXT_SUCCESS "──────────────────────"
  echo $message |
    sed -e "s/^ *#\{3,\} /  /g" | # インデントを調整してコメントアウトを削除
    sed -e "s/^ *## //g" | # コメントアウトを削除
    sed -e "s/^\( *-\{1,2\}[a-z][a-z-]*\)\(.*\)/  ${COLOR_NOTICE}\1\2${COLOR_RESET}/g" | # オプションを書式調整
    sed -e "s/\[\(.*\)\]/${COLOR_WARNING}\1${COLOR_RESET}/g" # []を着色
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
  unset -f $(cat $FUNCTIONS_PATH | grep -E '^[a-zA-Z_]+\(\) \{' | sed -e 's|^\(.*\)() {.*|\1|' | xargs -L 1)
}
