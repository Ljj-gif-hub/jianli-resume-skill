# 版式模板库

四套内置模板，**共享同一套契约**，随便换模板都不影响单页保证和 PDF 管线：

- `@page 615.1pt × 870pt`（margin 0）↔ `body 820 × 1160`（min-height）1:1 对应
- 密度档：`body.tier-compact`（13px）/ `body.tier-dense`（12px）
- 底部 fit 单页自适应脚本（zoom 等比缩放 + 60px 底部留白）

## 模板与关键词映射

| 模板 | 文件 | 触发关键词 | 风格 |
|---|---|---|---|
| 经典（默认） | `../resume-template.html` | 不带关键词 / 经典 / 商务 / 单栏 | 单栏蓝 accent，最稳 |
| 双栏 | `template-sidebar.html` | 双栏 / 侧栏 / sidebar | 左深色栏（联系/技能/自评）+ 右主栏（项目） |
| 极简 | `template-minimal.html` | 极简 / 简约 / 黑白 / 外企 / 学术 | 黑白灰细线，衬线标题 |
| 现代 | `template-accent.html` | 现代 / 彩色 / 渐变 / 设计感 / 年轻 | 渐变头部大色块 + 彩色强调 |

> **机筛提示**：网申 / BOSS 等机器解析 PDF 的场景投**经典单栏**——双栏版式被解析器按文本流读出时左右栏内容可能交错、字段张冠李戴；双栏 / 现代适合邮件附件、线下打印、人眼阅读。

> **头像**：模板默认引用 `_resume_assets/avatar.png`；目标项目没有这个文件时，删掉 `<img class="avatar">` 整行再填内容——headless 打印下 onerror 不可靠，留 404 引用会出破图。

## 新增自定义模板

1. 复制任意一份现有模板，改 CSS（配色 / 布局 / 字体）
2. **必须保留**：`@page` 尺寸、`body` 画布、tier 密度档、底部 `<script>` fit 脚本
3. 在上表加一行关键词映射，并同步 SKILL.md 的"模板选择"
