# スクリプト定数ファイル

# ファイルパス
local -r WORKSPACE="${HOME}/Workspace"
local -r SCRIPT_DIR="${HOME}/.zsh"
local -r EXPORT_DIR="${HOME}/Dropbox/Settings/Shell/zsh"
local -r TOOL_SCRIPT="${SCRIPT_DIR}/src/tool.sh"
local -r FUNCTIONS_PATH="${SCRIPT_DIR}/src/functions.sh"
local -r DEST_DIR="${WORKSPACE}/dist"

# アプリケーション
local -r BROWSER="/Applications/Safari.app"
local -r BROWSER_ALT="Google Chrome"
local -r APP_GIT_CLIENT="/Applications/Sourcetree.app"

# 出力文字色 (sedに対応するため\eではなく\x1bを使用)
local -r COLOR_RESET="\x1b[m"
local -r COLOR_WARNING="\x1b[33m"
local -r COLOR_DANGER="\x1b[31m"
local -r COLOR_NOTICE="\x1b[36m"
local -r COLOR_SUCCESS="\x1b[32m"
local -r COLOR_INFO="\x1b[34m"
local -r COLOR_INFO_DARK="\x1b[35m"
local -r COLOR_MUTED="\x1b[2m"
local -r TEXT_WARNING="${COLOR_WARNING}%s\n${COLOR_RESET}"
local -r TEXT_DANGER="${COLOR_DANGER}%s\n${COLOR_RESET}"
local -r TEXT_NOTICE="${COLOR_NOTICE}%s\n${COLOR_RESET}"
local -r TEXT_SUCCESS="${COLOR_SUCCESS}%s\n${COLOR_RESET}"
local -r TEXT_INFO="${COLOR_INFO}%s\n${COLOR_RESET}"
local -r TEXT_INFO_DARK="${COLOR_INFO_DARK}%s\n${COLOR_RESET}"
local -r TEXT_MUTED="${COLOR_MUTED}%s\n${COLOR_RESET}"

# デバッグコードが含まれていないか
local -r EMOJI_CHARS=(
  "🔥" "✨" "🌟" "💫" "💥" "💢" "💦" "💧" "💤" "💨" "💼" "👜" "💛" "💙" "💜" "💚" "❤" "💔" "💗" "💓"
  "💕" "💖" "💞" "💘" "💎" "💭" "💐" "🌸" "🌷" "🍀" "🌹" "🌻" "🌺" "🍁" "🍃" "🍂" "🌿" "🌾" "🍄" "🌵"
  "🌴" "🌲" "🌳" "🌰" "🌱" "🌼" "🌐" "🌍" "🌎" "🌏" "🌋" "🌌" "🌠" "⭐" "⛅" "⛄" "🌀" "🌁" "🌈" "🌊"
  "🎍" "🎒" "🎓" "🎏" "🎆" "🎇" "🎐" "🎑" "🎃" "👻" "🎄" "🎁" "🎋" "🎉" "🎊" "🎈" "🎌" "🔮" "🎥" "📷"
  "📹" "📼" "💿" "📀" "💽" "💾" "💻" "📱" "☎" "📞" "📟" "📠" "📡" "📺" "📻" "🔊" "🔉" "🔈" "🔇" "🔔"
  "🔕" "📢" "📣" "⏳" "⌛" "⏰" "⌚" "🔓" "🔒" "🔏" "🔐" "🔑" "🔎" "💡" "🔦" "🔆" "🔅" "🔌" "🔋" "🔍"
  "🛁" "🛀" "🚿" "🚽" "🔧" "🔩" "🔨" "🚪" "🚬" "💣" "🔫" "🔪" "💊" "💉" "💰" "💴" "💵" "💷" "💶" "💳"
  "💸" "📲" "📧" "📥" "📤" "✉" "📩" "📨" "📯" "📫" "📪" "📬" "📭" "📮" "📦" "📝" "📄" "📃" "📑" "📊"
  "📈" "📉" "📜" "📋" "📅" "📆" "📇" "📁" "📂" "✂" "📌" "📎" "✒" "✏" "📏" "📐" "📕" "📗" "📘" "📙"
  "📓" "📔" "📒" "📚" "📖" "🔖" "📛" "🔬" "🔭" "📰" "🎨" "🎬" "🎤" "🎧" "🎼" "🎵" "🎶" "🎹" "🎻" "🎺"
  "🎷" "🎸" "👾" "🎮" "🃏" "🎴" "🀄" "🎲" "🎯" "🏈" "🏀" "⚽" "⚾" "🎾" "🎱" "🏉" "🎳" "⛳" "🚵" "🚴"
  "🏁" "🏇" "🏆" "🎿" "🏂" "🏊" "🏄" "🎣" "☕" "🍵" "🍶" "🍼" "🍺" "🍻" "🍸" "🍹" "🍷" "🍴" "🍕" "🍔"
  "🍟" "🍗" "🍖" "🍝" "🍛" "🍤" "🍱" "🍣" "🍥" "🍙" "🍘" "🍚" "🍜" "🍲" "🍢" "🍡" "🍳" "🍞" "🍩" "🍮"
  "🍦" "🍨" "🍧" "🎂" "🍰" "🍪" "🍫" "🍬" "🍭" "🍯" "🍎" "🍏" "🍊" "🍋" "🍒" "🍇" "🍉" "🍓" "🍑" "🍈"
  "🍌" "🍐" "🍍" "🍠" "🍆" "🍅" "🌽" " " "🏠" "🏡" "🏫" "🏢" "🏣" "🏥" "🏦" "🏪" "🏩" "🏨" "💒" "⛪"
  "🏬" "🏤" "🌇" "🌆" "🏯" "🏰" "⛺" "🏭" "🗼" "🗾" "🗻" "🌄" "🌅" "🌃" "🗽" "🌉" "🎠" "🎡" "⛲" "🎢"
  "🚢" "⛵" "🚤" "🚣" "⚓" "🚀" "✈" "💺" "🚁" "🚂" "🚊" "🚉" "🚞" "🚆" "🚄" "🚅" "🚈" "🚇" "🚝" "🚋"
  "🚃" "🚎" "🚌" "🚍" "🚙" "🚘" "🚗" "🚕" "🚖" "🚛" "🚚" "🚨" "🚓" "🚔" "🚒" "🚑" "🚐" "🚲" "🚡" "🚟"
  "🚠" "🚜" "💈" "🚏" "🎫" "🚦" "🚥" "⚠" "🚧" "🔰" "⛽" "🏮" "🎰" "♨" "🗿" "🎪" "🎭" "📍" "🚩"
  "⬆" "⬇" "⬅" "➡" "🔠" "🔡" "🔤" "🔄" "◀" "▶" "🔼" "🔽" "↩" "↪" "ℹ" "⏪" "⏩" "⏫" "⏬" "🆗" "🔀"
  "🔁" "🚫" "❎" "✅" "❌" "⭕" "❗" "❓" "❕" "❔" "🔃" "🔘" "🔗" "⬜" "⬛" "⚫" "⚪" "🔴" "🔵" "🔻"
  "🔶" "🔷" "🔸" "🔹"
)

# 汎用メッセージ
local -r MESSAGE_PRODUCTION_ACCESS="${COLOR_DANGER}────────────────────────────────────\n⚠️  ACCESS TO PRODUCTION ENVIRONMENT!\n────────────────────────────────────${COLOR_RESET}"
local -r TEXT_ARGUMENT_ERROR="${COLOR_DANGER}Wrong argument. (expected: %s)${COLOR_RESET}\n"
