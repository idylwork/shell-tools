# Personal Shell Tools

## 概要

大きく分けて 2 つの機能をシェルに追加します。

### シェルスクリプトのユーティリティ関数

2 つのコマンドを追加します。

#### `to <action>`コマンド

Git や Docker などに関するスニペット集です。
第 2 引数にアクションを指定することで、さまざまな操作を行います。
ファイルを一括で名称変更したり、タイマーを表示したりといった便利コマンドのほか
プロジェクトのリポジトリ単位でのコマンドを使うと、プロジェクトのディレクトリ配下でコマンドを実行した際に
適した操作をするよう、設定ファイルにパスなどを保持しておくことができます。
各開発プロジェクトでタスク管理・コード管理・インフラ構成などを完全に統一して管理することは難しく
複数のプロジェクトを横断する際に、都度設定を確認したりドキュメントを参照する必要が出てしまいます。
プロジェクトごとの設定をファイルに保持しておくことで、情報へのアクセスやソースファイルの操作を迅速に行うことができるようになります。

一例として以下のようなコマンドがあります。詳細は`to help`で確認できます。

- `to develop` develop ブランチをチェックアウトして最新に更新する
- `to git pulls` Git の設定を読み取り、リポジトリのプルリクエストをブラウザで開きます
- `to open` Docker や Vagrant の設定を読み取り、ローカル環境の URL を開きます

#### `ws <ディレクトリ名>`コマンド

あいまい検索を使ってワークスペースディレクトリ内をスピーディに移動できます
プロジェクトのディレクトリに移動して`to`コマンドを併用することで
情報のアクセスやファイル操作を CLI で完結することもできます。

```sh
ws # ワークスペースルートに移動
mkdir example_project
ws expj # example_project に移動
```

### Git CLI の設定

フックを追加

## 利用方法

### シェルスクリプト

#### 導入

[index.sh](./index.sh) を読み込むことで各コマンドが追加されるので、`~/.zshrc`などに以下のコードを追加します。
.zshrc に関する他の設定は[zshrc_sample](./sample/zshrc_sample)を参照してください。

```sh
[ -f ~/.zsh/index.sh ] && source ~/.zsh/index.sh
```

設定が終わったらコマンドを読み込みなおします。

```sh
source ~/.zshrc
```

#### 利用

各コマンドの詳細はヘルプメッセージを参照してください。

```sh
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
