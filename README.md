<img src="./android/app/src/main/res/mipmap-xxhdpi/ic_launcher_round.png" alt="logo" width="144" height="144" align="right" />

# MyPixEz

使用 Flutter 编写的 pixiv 第三方客户端，基于 **[PixEz Flutter](https://github.com/Notsfsssf/pixez-flutter)** 的**个人定制版**。

在官方客户端的基础上，重点重做了一整套**看图阅读体验**（缩略图预览、Mihon 式点击分区、
预加载策略），并补上了搜索筛选等功能。

> **这是非官方版本，与原作者无关。**
> 请勿就本版本的问题去打扰原作者。
> 目前**只发布 Android 版本**。

---

## 下载

### [⬇️ 下载最新 APK](https://github.com/TianYuuu/MyPixEz/releases/latest)

| 项目 | 值 |
| --- | --- |
| 应用名 | MyPixez |
| 包名 | `com.tianyu.pixez` |
| 版本 | 0.9.110 |
| 最低系统 | Android 7.0（API 24） |
| 目标系统 | API 37 |
| 体积 | 约 49 MB（arm64-v8a 等全架构） |

包名和官方版**不一样**，所以可以和官方 PixEz **同时安装**，互不覆盖、互不影响。

---

## 这个版本改了什么

### 看图页（重点）

这是改动最多的地方，目标是**消除黑屏加载**和**让单手操作更顺**。

| 功能 | 说明 |
| --- | --- |
| **缩略图预览** | 进入图集立刻加载缩略图，滑动途中先用它顶上，停稳后再换成大图——避免了过去那种黑屏滚来滚去 |
| **底部缩略图横条** | 可滑动定位到任意页；支持**从右到左**的日漫阅读顺序；进入看图页就显示，不需要多点一次 |
| **全屏缩略图网格** | 横条上滑（或在画面上直接上滑）展开；95% 屏高；顶部带进度条和页码，拖进度条可直达任意页 |
| **缩略图形状** | `统一大小`（裁切对齐）/ `按原图比例`（完整显示，**横图竖图一眼可辨**）。设置里和网格右上角都有开关，两处**双向同步、即时生效** |
| **点击分区** | 照搬 Mihon：L 型 / Kindlish / Edge / 左右 / 关闭，共 5 种；支持**左右镜像**和**进入时提示层** |
| **预加载** | 可设置向后预取 3~10 页，**只取预览图，不取原图**，控制流量 |
| **长按下载** | 看图页长按直接下载**原图**；缩略图上长按则下载该页原图 |
| **悬浮页码** | 只在**没有任何 UI** 时显示，不和底部横条重复 |
| **单图作品** | 只有一张图也能呼出缩略图，行为和多图作品一致 |

### 搜索

| 功能 | 说明 |
| --- | --- |
| **页数筛选** | 只要页数在某个范围内的作品 |
| **观看数筛选** | 只要观看数达到某个量级的作品 |
| **点赞数筛选** | 同上 |
| **筛选弹窗重做** | 95% 屏高；顶栏固定不滚动（选项再多"应用"也点得到）；自定义筛选置顶；每项一行 `A — B` 手填数字 |

> ⚠️ 这三个筛选都是**纯本地过滤**（过滤已经加载出来的结果），所以翻页时结果会越来越少。
> 这么做是为了**零额外请求**。详见下面的[已知限制](#已知限制)。

### 图集详情页

- 左下角加了两个悬浮按钮，和右下角的**收藏按钮左右对称**：
  - 上面一个：**回到页面最上方**（浏览器那种 Top 键）
  - 下面一个：**定位到作者 / 介绍 / 标签区**，翻完一堆图之后不用手划回去

### 其他

- 新增一批设置项：点击分区模式、镜像、提示层、阅读方向、缩略图条开关、
  页码指示、网格列数、横条方向、横条格宽、滑动触感、预加载页数、缩略图形状等
- App 名称改为 `MyPixez`，包名改为 `com.tianyu.pixez`
- 修复了详情页定位在长图集下会卡住、画质加载偶发黑屏等问题

完整的改动清单和设计取舍记录在 **[CUSTOMIZATIONS.md](CUSTOMIZATIONS.md)**。

---

## 安装

1. 在 [Releases](https://github.com/TianYuuu/MyPixEz/releases/latest) 下载 `app-release.apk`
2. 手机上打开该文件，允许"安装未知来源应用"
3. 安装完成后打开即可

**可以和官方 PixEz 共存**，两个 App 数据独立、登录状态互不影响。

---

## 从源码构建

> ⚠️ **克隆下来不能直接 `flutter build`**。本项目把生成文件（`*.g.dart`、
> `*.freezed.dart`、`lib/src/generated/`）都做了 gitignore（沿用上游做法），
> **少走下面任意一步都会编译失败**。

```bash
git clone https://github.com/TianYuuu/MyPixEz.git
cd MyPixEz

flutter pub get

# 生成 json_serializable / mobx / freezed 代码
dart run build_runner build --delete-conflicting-outputs

# 生成国际化代码（注意：build_runner 不会替你跑这个）
flutter gen-l10n

# 构建
flutter build apk --release
```

产物在 `build/app/outputs/flutter-apk/app-release.apk`。

### 环境要求

作者验证过的一套版本，**版本对不上容易出奇怪的编译错误**：

| 组件 | 版本 |
| --- | --- |
| Flutter | 3.47.7（stable） |
| Dart SDK | `>=3.11.5` |
| JDK | 21 |
| Android NDK | 28.2.13676358 |
| Rust | 1.99.0（`plugins/rhttp` 需要，目标 `aarch64-linux-android`） |

### 签名

仓库里**不包含**签名文件。`android/key.properties` 已在 `.gitignore` 中，
没有它时 Gradle 会回退到 debug 签名，能构建但无法覆盖安装正式包。

### iOS

iOS 的源码和配置都在仓库里（bundle id 同样改成了 `com.tianyu.pixez`），
但**本仓库暂不提供 iOS 构建产物**。

---

## 已知限制

这些是当前版本的已知行为，不是 bug：

1. **搜索的观看数 / 点赞数 / 页数筛选是本地过滤**，只作用于已加载的结果，
   翻页时会越翻越少。pixiv 的接口只原生支持点赞数区间（`bookmark_num_min/max`），
   为了三种筛选行为一致，统一走了本地过滤。
2. **无法按作者粉丝数筛选**。搜索结果里的作者对象只有 id / 名字 / 账号 / 头像，
   **没有粉丝数**；要拿必须对每个作者再请求一次，几百个结果就是几百次请求，
   有触发限流甚至封号的风险，所以没做。
3. **缩略图网格无法让格子本身变形**。模型的每页数据里只有图片地址、没有宽高，
   所以"按原图比例"是用 `BoxFit.contain` 让图片在自己的方格里完整显示，
   而不是让格子跟着图片比例变。
4. **底部缩略图横条固定格宽**。居中的滚动算法依赖统一宽度，所以横条不随形状设置改变宽度。
5. **预加载只向后（下一页方向）**，不向前。
6. 这是**个人自用版本**，功能以作者自己的使用习惯为准，不保证通用性。

---

## 许可

[GPL-3.0](LICENSE)，与原项目一致。

本项目是 [Notsfsssf/pixez-flutter](https://github.com/Notsfsssf/pixez-flutter)
的衍生作品，**保留了原始版权声明**，并同样以 GPL-3.0 开源。

---

## 致谢

原始项目：[Notsfsssf/pixez-flutter](https://github.com/Notsfsssf/pixez-flutter)

上游贡献者：

<table>
  <tr>
    <td align="center"><a href="https://github.com/Notsfsssf"><img src="https://avatars3.githubusercontent.com/u/16934707?v=4" width="100px;" alt=""/><br /><sub><b>Perol_Notsfsssf</b></sub></a><br /><a href="https://github.com/Skimige/pixez-flutter/commits?author=Notsfsssf" title="Code">💻</a></td>
    <td align="center"><a href="https://xyx.moe"><img src="https://avatars3.githubusercontent.com/u/9017470?v=4" width="100px;" alt=""/><br /><sub><b>Skimige</b></sub></a><br /><a href="https://github.com/Skimige/pixez-flutter/commits?author=Skimige" title="Documentation">📖</a></td>
    <td align="center"><a href="https://github.com/TragicLifeHu"><img src="https://avatars3.githubusercontent.com/u/16817202?v=4" width="100px;" alt=""/><br /><sub><b>Tragic Life</b></sub></a><br /><a href="#translation-TragicLifeHu" title="Translation">🌍 (zh_TW)</a></td>
    <td align="center"><a href="http://ivtune.net"><img src="https://avatars0.githubusercontent.com/u/54385201?v=4" width="100px;" alt=""/><br /><sub><b>karin722</b></sub></a><br /><a href="#translation-karin722" title="Translation">🌍 (ja)</a></td>
    <td align="center"><a href="http://archman.fun"><img src="https://avatars0.githubusercontent.com/u/68731023?v=4" width="100px;" alt=""/><br /><sub><b>Romani-Archman</b></sub></a><br /><a href="https://github.com/Skimige/pixez-flutter/commits?author=Romani-Archman" title="Documentation">📖</a></td>
    <td align="center"><a href="https://github.com/itzXian"><img src="https://avatars1.githubusercontent.com/u/34748039?v=4" width="100px;" alt=""/><br /><sub><b>Xian</b></sub></a><br /><a href="#translation-itzXian" title="Translation">🌍 (en_US)</a></td>
    <td align="center"><a href="https://github.com/ReikiAigawara"><img src="https://avatars1.githubusercontent.com/u/66962815?v=4" width="100px;" alt=""/><br /><sub><b>Reiki Aigawara</b></sub></a><br /><a href="#translation-ReikiAigawara" title="Translation">🌍 (id_ID)</a></td>
  </tr>
</table>

上游还有[英文](.github/README_en.md)和[印尼文](.github/README_id.md)说明。

使用的第三方库：`mobx`、`provider`、`flutter_bloc`（逐步弃用）、`custompainter`（播放 ugoira）。
