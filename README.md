# Personal Shell Tools

## 概要

エンジニアとしてプロジェクトに関わるとき、ソースコードの編集や精査が業務の中心となってきます。
一方でプロジェクトの進行管理やソースコードのリリース先などはクライアントやインフラ構成によって変わってきます。
複数のプロジェクトに横断的に関わるとき、ブラウザのブックマークから辿って情報を検索するよりも
ソースコードに対してプロジェクト進行やドキュメントの管理場所を紐づけてしまおうという思想で機能を整備しています。

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
.zshrc に関する他の設定は[zshrc.sample](./sample/zshrc.sample)を参照してください。

```sh
[ -f ~/.zsh/index.sh ] && source ~/.zsh/index.sh
```

設定が終わったらコマンドを読み込みなおします。

```sh
source ~/.zshrc
```

コマンドを使って設定ファイルを配置します。

```sh
to edit --init
```

#### 利用

各コマンドの詳細はヘルプメッセージを参照してください。

```sh
: ヘルプメッセージの表示
to help
```

### Git 設定

[/git 配下](./git/)のファイルを`~/gitconfig`に組み込むことで Git にさまざまな設定が追加されます。

- `gitignore` 汎用的なグローバルの Gitignore 設定
- `pre-commit` コミット時、変更点にデバッグコードが含まれる場合はコミットを中止する
- その他設定

#### 導入

[gitconfig.sample.ini](./sample/gitconfig.sample)にサンプル設定があるため、各項目を適宜`~/.gitconfig`に反映してください。
以下コマンドで差分を表示できます。

```sh
to git init
```

#### 利用

Git の挙動がすべてのリポジトリで変更されるため、特別な操作は不要です。

## ディレクトリ構成

- index.sh スクリプトを読み込む
- src/ シェルスクリプトのコード
  - tool.sh `to`コマンド本体
  - constants.sh 定数週
  - functions.sh
  - settings.sh
- git/ Git の設定に関するファイル
- config/ 設定ファイル
  - addon.sh 追加のスクリプト
  - projects.ini プロジェクトごとの定数の設定
  - store.ini 保持したいデータ (`to bl`使用時の索引)
  - note.txt `to note`使用時に原稿として使用
- sample/ サンプルファイル
  - config/ 設定ファイルのサンプル (`to edit --init`で配置)
  - gitconfig.sample `~/.gitconfig`のサンプル
  - zshrc.sample `~/.zshrc`のサンプル

特定のプロジェクトに関するコードや設定は`config/`配下に記載するようにしてください

### projects.ini
セクションにフォルダ名を指定すると、一致するフォルダ配下を特定のプロジェクトと紐づけることができます。
プロジェクトに紐づく設定はここに設定します。
`[default]`セクションのみ特別で、プロジェクトに設定がなかったときのみこの値が使用されます。

- `BASE_BRANCH` Gitのベースブランチを指定します。
- `BRANCH_PREFIX` よく使うブランチ名の接頭辞を指定します。ブランチ名を指定する際に数字のみ指定すると自動的に接頭辞が使用されます。
- `BACKLOG_SPACE_ID` プロジェクトにBacklogがある場合、スペースIDを指定します。
- `BACKLOG_PROJECT_KEY` プロジェクトにBacklogがある場合、プロジェクトキーを指定します。
- `SSH_NAME_PRODUCTION` 本番サーバーのSSH接続名を指定します。
- `SSH_NAME_STAGING` ステージングサーバーのSSH接続名を指定します。
- `DOMAIN_PRODUCTION` 本番環境のドメインを指定します。
- `DOMAIN_STAGING` ステージング環境のドメインを指定します。
- `DEPLOY_TYPE` サーバーへのソースコードの反映方式を指定します。[dist: ファイルリリース, deployer: サーバー配置のDeployer, addon: addon.shの動作を参照]
- `DEPLOY_DIST_TARGET_DIR` DEPLOY_TYPEが`dist`の場合にリリース対象にするディレクトリパス。
- `APP_DIR` 各サーバーのアプリケーションルートパス。
- `LOG_FILE_PATH` アプリケーションのメインとなるログファイルのパス。
- `LOG_FILE_PATH_PRODUCTION` リモート環境でアプリケーションのメインとなるログファイルのパス。
- `URL_PATH_FRONT` フロントのホームページパス。
- `URL_PATH_ADMIN` 管理画面のログインページパス。
- `VM_PLATFORM` 仮想マシンの種別 [docker: Docker, vagrant: Vagrant]
- `VAGRANT_SSH_PROTOCOL` Vagrant環境がSSL対応になっているか。 [true, false]

### store.ini
データを保管するのに利用します。

### file_backup セクション
`to backup`コマンドに使用します。

キー名は判別しやすいものを設定します。`_archive`を末尾につけるとコピー先のファイルを削除しないようになります。
半角スペース区切りでコピー元・コピー先の順に設定します。
ホームディレクトリは`~/`、ファイルやフォルダ名のスペースは`\ `で表現してください。

```ini
[backup_paths]
itunes_library = ~/Music/iTunes /Music/iTunes
```

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
