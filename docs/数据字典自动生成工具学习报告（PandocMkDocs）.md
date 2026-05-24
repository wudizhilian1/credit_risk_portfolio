# 数据字典自动生成工具学习报告（Pandoc/MkDocs）

## 一、核心背景与目标

在数据开发（如风控数仓、业务数据表建设）中，数据字典是描述表结构、字段含义、数据类型、业务规则的核心文档，手动维护易出现 “文档与表结构不一致”“更新不及时” 等问题。本次学习聚焦**数据字典自动生成工具**（Pandoc、MkDocs），并探索基于 Python 脚本读取 DuckDB 系统表、将 DDL 注释转化为标准化 Markdown 数据字典的落地路径。

## 二、主流数据字典自动生成工具详解

### 1. Pandoc

- **定位**：跨格式文档转换工具，核心能力是 “格式转换”，而非直接生成数据字典，可作为数据字典的 “格式适配层”。

- 核心原理：

  - 支持将纯文本、HTML、LaTeX、JSON 等格式转换为 Markdown、Word、PDF、HTML 等，适配不同场景的文档输出需求；
  - 无原生的数据表结构解析能力，需先通过脚本生成基础格式文档（如 Markdown/JSON），再用 Pandoc 转换为最终格式（如企业要求的 PDF 数据字典）。

- 适配场景：

  - 已生成 Markdown 数据字典后，需转换为 PDF/Word 供非技术人员查阅；
  - 统一数据字典的输出格式（如批量将多份 Markdown 字典转为 HTML 静态页）。

- 基础用法：

  ```bash
  # 将 Markdown 数据字典转为 PDF（需提前安装 LaTeX 环境）
  pandoc data_dictionary.md -o data_dictionary.pdf
  
  # 将 Markdown 转为 Word 文档
  pandoc data_dictionary.md -o data_dictionary.docx
  ```

### 2. MkDocs

- **定位**：基于 Python 的静态站点生成工具，主打 “Markdown 文档→可视化静态网站”，适合构建可在线浏览、可检索的结构化数据字典平台。

- 核心原理：

  - 以 Markdown 文件为数据源，通过配置 `mkdocs.yml` 定义文档目录结构、导航栏、主题样式；
  - 内置本地预览服务，支持一键部署到 GitHub Pages、服务器等，生成的静态网站支持全文检索、目录导航，体验优于纯 Markdown 文件。

- 适配场景：

  - 构建企业级数据字典门户，供开发、测试、业务人员在线查阅；
  - 结合自动化脚本，实现 “表结构变更→Markdown 字典更新→静态网站自动刷新” 的闭环。

- 核心流程：

  1. 安装：`pip install mkdocs`；
  2. 初始化项目：`mkdocs new data_dictionary`；
  3. 将自动生成的 Markdown 数据字典放入 `docs` 目录；
  4. 配置 `mkdocs.yml` 定义导航（如按数据库 / 表分类）；
  5. 本地预览：`mkdocs serve`（访问 http://127.0.0.1:8000）；
  6. 构建静态网站：`mkdocs build`（输出到 `site` 目录）。

  

## 三、核心落地方案：DDL 注释→DuckDB→Markdown 数据字典

### 1. 技术思路

通过 Python 脚本读取 DuckDB 系统表（存储表结构、字段注释等元数据），解析 DDL 注释信息，自动生成标准化 Markdown 格式的数据字典，再通过 Pandoc/MkDocs 实现格式转换或可视化部署。

### 2. 关键步骤（Python + DuckDB 实现）

#### 步骤 1：读取 DuckDB 系统表获取元数据

DuckDB 提供 `information_schema` 系统库，存储所有表 / 字段的元数据，核心表：

- `information_schema.tables`：表级信息（表名、创建时间、表注释）；
- `information_schema.columns`：字段级信息（字段名、数据类型、字段注释、是否主键、默认值）。

#### 步骤 2：Python 脚本核心逻辑

```python
import duckdb
import os

# 1. 连接 DuckDB 数据库
conn = duckdb.connect(database='your_database.duckdb', read_only=True)

# 2. 定义要生成字典的表名（可批量配置）
target_tables = ['risk_user', 'risk_loan', 'risk_overdue']

# 3. 生成 Markdown 数据字典
output_dir = 'data_dictionary'
os.makedirs(output_dir, exist_ok=True)

for table in target_tables:
    # 3.1 查询表级注释（若 DDL 中添加了表注释）
    table_comment_sql = f"""
    SELECT obj_description('{table}'::regclass) AS table_comment;
    """
    table_comment = conn.execute(table_comment_sql).fetchone()[0] or '无'

    # 3.2 查询字段级信息
    column_sql = f"""
    SELECT 
        column_name,
        data_type,
        is_nullable,
        column_default,
        column_comment  -- DuckDB 需确保字段注释已通过 COMMENT 语句添加
    FROM information_schema.columns 
    WHERE table_name = '{table}';
    """
    columns = conn.execute(column_sql).fetchall()

    # 3.3 生成 Markdown 内容
    md_content = f"""# 表：{table}
## 表说明
{table_comment}

## 字段列表
| 字段名 | 数据类型 | 是否可为空 | 默认值 | 字段注释 |
|--------|----------|------------|--------|----------|
"""
    for col in columns:
        col_name, data_type, is_nullable, default, comment = col
        default = default or '无'
        comment = comment or '无'
        md_content += f"| {col_name} | {data_type} | {is_nullable} | {default} | {comment} |\n"

    # 3.4 保存 Markdown 文件
    with open(os.path.join(output_dir, f'{table}_dict.md'), 'w', encoding='utf-8') as f:
        f.write(md_content)

# 4. 关闭连接
conn.close()
print("数据字典生成完成！")
```

#### 步骤 3：适配 Pandoc/MkDocs 扩展

- **Pandoc 转换**：执行 `pandoc data_dictionary/risk_user_dict.md -o risk_user_dict.pdf`，将单表字典转为 PDF；

- **MkDocs 部署**：将生成的所有 Markdown 文件放入 MkDocs 项目的 `docs` 目录，配置 `mkdocs.yml` 导航：

  ```yaml
  site_name: 风控数据字典
  nav:
    - 首页: index.md
    - 用户表: risk_user_dict.md
    - 放款表: risk_loan_dict.md
    - 逾期表: risk_overdue_dict.md
  theme: readthedocs  # 简洁易读的主题
  ```

### 3. 关键注意事项

- **DDL 注释规范**：需确保建表时通过 `COMMENT` 语句添加表 / 字段注释（如 `COMMENT ON COLUMN risk_user.user_id IS '用户唯一标识'`），否则系统表无注释信息；
- **批量扩展**：可将 `target_tables` 改为从配置文件读取，支持全库表自动生成；
- **特殊字段处理**：对主键、外键、枚举类型字段，需在脚本中额外标注，提升字典可读性。

## 四、落地价值与优化方向

### 1. 核心价值

- **自动化**：替代手动编写数据字典，避免 “文档与表结构不一致”；
- **标准化**：统一数据字典格式，便于团队协作与查阅；
- **可扩展**：结合 Pandoc/MkDocs 适配不同输出形式，满足多角色使用需求；
- **适配风控场景**：快速生成风控核心表（用户风险、放款、逾期）的字典，支撑模型开发、策略配置的业务理解。

### 2. 长期优化方向

- **增量更新**：监听 DuckDB 表结构变更，仅更新变更表的字典，避免全量生成；
- **权限控制**：基于 MkDocs 集成简单的权限验证，确保敏感风控数据字典仅授权人员可查看；
- **可视化增强**：在 MkDocs 中添加字段关联关系图、数据分布说明，丰富字典维度；
- **CI/CD 集成**：将字典生成脚本加入 Git CI/CD 流程，表结构合并后自动更新字典并部署。

## 五、核心总结

1. Pandoc 是 “格式转换工具”，适配 Markdown 字典转 PDF/Word；MkDocs 是 “静态站点工具”，适合构建可在线浏览的数据字典门户；
2. 核心落地路径：Python 读取 DuckDB 系统表 → 解析 DDL 注释 → 生成 Markdown 字典 → Pandoc/MkDocs 扩展输出；
3. 关键前提：需规范 DDL 注释编写，确保系统表可提取到表 / 字段的业务含义；
4. 风控场景价值：自动化生成风控核心表字典，提升数据文档的及时性、准确性，降低协作成本。