## 利用方法

### シェルスクリプト

#### 導入

[index.sh](./index.sh) を読み込むことで各コマンドが追加されます。

- `to` Git や Docker などに関するスニペット集
- `ws <ディレクトリ名>` ワークスペースディレクトリ内をスピーディに遷移する

`~/.zshrc`などに以下のコードを追加します。
.zshrc に関する他の設定は[zshrc_sample](./sample/zshrc_sample)を参照してください。

```sh
[ -f ~/.zsh/index.sh ] && source ~/.zsh/index.sh
```

#### 利用

ヘルプメッセージを参照してください。

```sh
: ZSH設定の再読み込み
source ~/.zshrc

: ヘルプメッセージの表示
to help
```

### Git 設定

#### 導入

[gitconfig_sample.ini](./sample/gitconfig_sample) の設定を反映することで Git にさまざまな設定が追加されます。

- `gitignore` グローバルな Gitignore 設定
- `pre-commit` コミット時、変更点にデバッグコードが含まれる場合はコミットを中止する
- その他設定

#### 利用

Git の挙動がすべてのリポジトリで変更されるため、特別な操作は不要です。

## ディレクトリ構成

- index.sh スクリプトを読み込む
- src シェルスクリプトのコード
- git Git の設定に関するファイル
- config 設定ファイル
  - addon.sh 追加のスクリプト
  - projects.ini プロジェクトごとの定数の設定
  - store.ini 保持したいデータ (`to bl`使用時の索引)
  - note.txt `to note`使用時に原稿として使用
- sample サンプルファイル
  - addon_sample.sh `config/addon.sh`のサンプル
  - gitconfig_sample `~/.gitconfig`のサンプル
  - projects_sample.ini のサンプル `config/projects.ini`のサンプル
  - zshrc_sample `~/.zshrc`のサンプル

特定のプロジェクトに関するコードや設定は`config/`配下に記載するようにしてください

## Homebrew

以下のライブラリを導入しています。

- git
- nodenv

## シェルスニペット

時々使用するスニペットをここに記載しておきます。

```sh
: 1時間以内に更新されたファイル
sudo find . -mmin -60 -type f | xargs ls -l {}

: 代替treeコマンド
pwd; find . | sort | sed '1d;s/^\.//;s/\/\([^/]*\)$/|--\1/;s/\/[^/|]*/|  /g' && echo -e "\n$(find . -type d | wc -l) directories, $(find . -type f | wc -l) files"
```
