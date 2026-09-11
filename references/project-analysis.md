# 项目指纹分析（任意项目通用）

目标：快速识别出"这是什么项目、用什么技术、规模多大、有哪些可写进简历的证据"。所有数字必须来自 grep/glob 统计，不估算。

## 1. 技术栈识别

按优先级在当前目录或子目录检测 manifest：

| Manifest | 语言 / 生态 | 再看框架 |
|---|---|---|
| package.json | JavaScript / TypeScript | vue / react / angular / next / nuxt；移动端 uni-app / taro |
| pom.xml / build.gradle / build.gradle.kts | Java | spring-boot / spring-mvc / mybatis / mybatis-plus / netty / Android |
| requirements.txt / pyproject.toml / Pipfile / setup.py | Python | fastapi / flask / django / langchain / langgraph / scrapy |
| go.mod | Go | gin / echo / beego / kratos |
| *.csproj / *.sln | C# / .NET | ASP.NET Core / WPF / Unity |
| Cargo.toml | Rust | axum / actix / tokio |
| composer.json | PHP | Laravel / ThinkPHP |
| Gemfile | Ruby | Rails |
| pubspec.yaml | Flutter / Dart | — |
| AndroidManifest.xml / settings.gradle | Android | Kotlin / Java |
| *.xcodeproj / *.xcworkspace | iOS | Swift / Objective-C |
| 大规模 *.c / *.h / *.cpp | C / C++ | 看 CMakeLists.txt / Makefile / Qt |
| *.sql / *.ddl / migration/ | 数据相关 | 数据库类型 |
| Dockerfile / docker-compose.yml | 容器化 | 编排技术 |

多端项目（web + app + 后端服务）要分别识别，并说明三者关系（谁调谁）。

## 2. 领域识别（产品是干什么的）

- 读 README.md 前 30 行、CLAUDE.md（如有）
- 看顶层目录 / 模块名：`order-service`、`payment`、`user` 说明是电商/业务系统
- 看主要 entity / model / 表名
- 一句话概括：**为谁解决什么问题**（简历里产品定位就是这句话）

## 3. 规模量化（简历数字来源）

用 Grep/Glob 统计真实数量：

- 后端：`@Controller` / `@RestController`、`@Service`、`@Repository` / `@Mapper` 注解数；实体类数；路由定义数
- 前端：路由表条目数；`views/` / `pages/` 文件数；`components/` 组件数；store 数量；i18n 语言数
- 数据库：schema.sql / 迁移文件中的表数量
- 测试：`@Test` / `it(` / `test_` 数量，以及覆盖的模块
- 工程：定时任务、MQ 消费者、第三方 API 对接（地图/支付/LLM/搜索）数量

> 简历写"9+ 业务模块 / 27 个接口 / 50+ 组件"这类**真实统计**，比编造精确数更有说服力。

## 4. 部署与工程质量证据

- `Dockerfile` / `docker-compose.yml` / k8s 清单 → 容器化编排
- `.github/workflows` / `.gitlab-ci.yml` / `Jenkinsfile` → CI/CD
- `nginx.conf` 或反代配置 → 网关/负载
- `scripts/` 运维脚本、部署文档 → 上线流程
- 文档中可访问的 URL → "已上线"证据
- 监控：Prometheus / Actuator / Sentry / 日志体系
- `.gitignore` 里排除 .env 等 → 安全实践

## 5. 提取"你的贡献"

1. `git config user.name` 拿身份（可能是中文名 / 拼音 / 缩写如 LJJ）
2. `git log --author=<身份> --oneline -50` 拉你的提交
3. 从提交信息识别主导功能与疑难修复：`修复` `重构` `上线` `优化` `安全` 类是亮点
4. 若仓库有多位作者：`git shortlog -sne` 看分布，确认自己的工作边界后只写自己做的
5. 项目文档（CHANGELOG、DEPLOYMENT_*、FIXES_*、REVIEW_*）常记录你主导的**线上排障**——简历里"线上定位并修复 X"这类句子全靠它们
6. 你的工作用"我实现/我主导"表述，与"我们"严格区分

## 6. 兜底

任何一步识别不出（空仓库、新项目、只认得出少量代码）→ **停止猜测**，直接问用户：
"这个项目用了什么技术栈？你负责了哪些部分？" 以用户回答为准，不编造。
