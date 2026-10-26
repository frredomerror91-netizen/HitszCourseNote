# 第7章｜pyecharts绘图

## 本章要学什么

本章解决“把核验后的表格指标变成可交互图表与分析页”。先学对象和配置，再按比较、趋势、构成等问题选择图形，最后组织页面。先修为Python列表、字典及按组汇总；表内索引与真实数值在使用处区分。所有代码使用固定教学数据，HTML生成不等于离线可用。

## 本章学习地图

| 学习阶段 | 要回答的问题 | 可检验成果 |
| --- | --- | --- |
| 对象与配置 | Python和浏览器各做什么？ | 导出并抽查一张图 |
| 基本图类 | 问题需要哪种编码？ | 核对类别、数值和分母 |
| 特殊结构 | 输入是五数、点还是边？ | 检查图类的数据结构 |
| 组合页面 | 怎样安排阅读与时间？ | 建立多图页与一致时间帧 |

## 一、从Python对象到交互网页（7.1—7.3）

### 本章路线

本章要解决的问题：交互图究竟在哪里绘制，配置怎样生效？本章学完应会：建立图表对象、核对序列对应，分清全局与系列配置。

### 学习单元

> 题源：依课程课件7.1—7.3及配套示例自编变式；本节小练习和检验同源，数据均为教学示例。

#### Python组织配置，浏览器执行绘图

pyecharts 用Python组织图表数据和配置，ECharts 在浏览器中完成显示与交互。`render` 写出HTML，`render_notebook` 提供Notebook内的显示表示；它们不会代替前面的数据清洗与统计。悬停提示、图例开关和缩放是读图功能，不能补救错误数据。

下面固定3个月销售额，避免随机示例每次变化。所有代码沿用课程pyecharts 2.x接口；先安装课程环境中的pyecharts，再执行。

```python
from pyecharts.charts import Bar
from pyecharts import options as opts
months = ["Apr", "May", "Jun"]
sales = [100, 150, 120]
chart = (
    Bar(init_opts=opts.InitOpts(width="900px", height="500px"))
    .add_xaxis(months)
    .add_yaxis("Sales", sales,
                 label_opts=opts.LabelOpts(position="top"))
    .set_global_opts(
        title_opts=opts.TitleOpts(title="Monthly sales"),
        yaxis_opts=opts.AxisOpts(name="Yuan"),
        tooltip_opts=opts.TooltipOpts(trigger="axis"))
)
chart.render("monthly_sales.html")
```

链式调用是让多个方法依次配置同一个对象；分行写 `chart.add_xaxis(...)` 等也可以。横轴第i项对应每个系列第i个值，因此必须一起排序、补齐。核验时悬停May，应显示Sales=150；图例关闭Sales后该系列应消失。

HTML不一定离线可用：默认生成页可能通过外部地址加载ECharts运行库。断网打开后空白，先查依赖是否加载和浏览器报错，再查数据；要离线分享，应提供对应的本地运行库并修改资源路径，或按项目既有离线方案打包，不能只改文件后缀。

##### 小练习：排序后为什么图错了

类目原为["B","A"]，值为[20,50]；只把类目排为["A","B"]再绘图会怎样？

**答案：** A被错误配成20、B变成50。应排序成对记录，得到A=50、B=20；列表长度相同只是必要条件，位置语义也要一致。

#### 全局配置管整图，系列配置管数据表现

`TitleOpts/AxisOpts/TooltipOpts/LegendOpts` 通常放进 `set_global_opts`，分别控制标题、轴、提示与图例。`LabelOpts/ItemStyleOpts/MarkPointOpts` 可作用于系列，控制标签、颜色与特征点；`set_series_opts` 则批量修改已有系列，要留意是否覆盖此前差异设置。

例如给上例添加 `MarkPointOpts(data=[MarkPointItem(type_="max")])` 到Sales系列，会按该系列数据定位150，而不是把最大横轴类目标出。`DataZoomOpts` 设置可见范围，`VisualMapOpts` 设置值到颜色等视觉通道的映射；两者不负责重新计算指标。

##### 小练习：把单位放在哪一层

一图比较两家店销售额，单位都为元，需要一个单位轴名和各自不同颜色，如何分工？

**答案：** `yaxis_opts=AxisOpts(name="Yuan")` 放全局；两次 `add_yaxis` 各自用 `itemstyle_opts` 设置颜色。若最后统一覆盖所有系列颜色，两店差异可能消失。

### 本章小结

图表是数据与配置的组合，必须先保证逐项对应。导出成功只证明文件生成，浏览器依赖和交互还需验证。

### 本章练习与检验

横轴3个月，第二系列只有2个数，能否在缺失月份直接填0？给出核验步骤。

**答案：** 先查缺失是“未采集”还是“确认零”，只有后者能填0；保留月份顺序并用明确缺失值表示未知。核对长度后，逐月抽查系列数值与源表，不能只看HTML是否存在。

## 二、比较、趋势与构成采用不同数据结构（7.4—7.7）

### 本章路线

本章要解决的问题：柱形、折线、饼和散点应如何选择并供数？本章学完应会：为问题选图，区分分类轴与数值轴，正确解释占比分母。

### 学习单元

> 题源：依课程课件7.4—7.7及配套示例自编变式；本节小练习和检验同源，数据均为教学示例。

#### 柱形看类别，折线看有序变化

Bar 连续添加两组系列形成分组柱形；两组都指定相同 `stack` 名才合并堆叠。A店[10,20]、B店[30,40]，堆叠总高分别40、60，只适合两个系列可以相加的情形；不能把金额与人数堆叠。

```python
from pyecharts.charts import Bar, Line
from pyecharts import options as opts
bar = (Bar().add_xaxis(["Tea", "Coffee"])
       .add_yaxis("A", [10, 20], stack="Total")
       .add_yaxis("B", [30, 40], stack="Total"))
horizontal = (Bar().add_xaxis(["Long category A", "Long category B"])
              .add_yaxis("Sales", [40, 60]).reversal_axis())
trend = (Line().add_xaxis(["Apr", "May", "Jun"])
         .add_yaxis("Sales", [100, 150, 120],
            areastyle_opts=opts.AreaStyleOpts(opacity=0.2)))
```

`reversal_axis()` 将类别与数值方向交换，长类目更易读；并不自动按数值排序。面积填充强调数量随有序横轴的变化，不能把任意无序商品连线后解读成时间趋势。`is_smooth=True` 改变连接外观，不增加真实采样点，可能夸大未观测位置的走势。

##### 小练习：堆叠能否表达完成率

目标100、实际80，若把它们堆叠成180，会怎样误导？怎样表达实际占目标比例？

**答案：** 目标与实际不是可相加的两个组成部分。可并列比较100和80；若要表示构成，拆成已完成80和未完成20，完成率80/100=80%。

#### Pie接收名称与数值对，Scatter需要数值横轴

Pie 使用 `(名称,数值)` 对，不走Bar的两列表接口。内外半径不同形成圆环，玫瑰图进一步用半径或面积表达差异；它们都需要非负值与明确总量。精确比较接近的数值时，排序条形通常更容易读。

```python
from pyecharts.charts import Pie, Scatter
parts = [("A", 60), ("B", 30), ("Other", 10)]
pie = (Pie().add("Sales", parts, radius=["40%", "70%"],
                label_opts=opts.LabelOpts(formatter="{b}: {d}%")))
scatter = (Scatter().add_xaxis([1., 3., 10.])
           .add_yaxis("Observations", [2., 4., 5.])
           .set_global_opts(xaxis_opts=opts.AxisOpts(type_="value", name="X")))
```

`{b}` 是类目名、`{c}` 是数值、`{d}` 是饼图该项在当前数据总和中的百分比。上例A占60%。如果删去Other，A会显示60/90约66.7%，那是所展示部分内部的占比。散点横轴若误设为类别轴，1、3、10可能等距排列，数值间隔便被误读；EffectScatter增加涟漪强调，不是新的统计方法。

##### 小练习：TOP项的占比分母

全店总额1000，前两商品为300和200，仅将两项送入Pie后会显示多少？怎样保留全店口径？

**答案：** 显示60%和40%，不是全店30%和20%。加入Other=500，或改用条形图并写出全店占比；不能仍称两项为全店构成100%。

### 本章小结

选图先看变量的关系：类别比较、有序变化、整体构成或数值配对。代码接口和坐标类型必须与该关系一致。

### 本章练习与检验

设备数[10,20]、销售额[100,180]同月显示，可否同轴堆叠？应怎样安排？

**答案：** 不可，单位不同。可分成上下两个共享月份的图；若使用双轴，明确每条系列对应的轴和单位，并提醒读者不能凭线条交叉比较数值大小。

## 三、特殊图先核对输入与含义（7.8—7.10）

### 本章路线

本章要解决的问题：图类很多时，怎样抓住各自必须满足的数据条件？本章学完应会：构造五数、三元组、节点与边、阶段人数及词频。

### 学习单元

> 题源：依课程课件7.8—7.10及配套示例自编变式；本节小练习和检验同源，数据均为教学示例。

#### 箱线与三维：五个统计量或三个坐标

箱线图每个箱子的数据次序为 `[下端,Q1,中位数,Q3,上端]`。课程使用 `Boxplot.prepare_data` 从原始列表计算五数；其计算与Seaborn默认1.5IQR箱须的处理不能混为一谈。pyecharts该辅助函数会保留最小、最大值，不会自动替你另列离群点；分位数插值约定也应固定。

```python
from pyecharts.charts import Boxplot, Bar3D, Scatter3D
from pyecharts import options as opts
box = Boxplot().add_xaxis(["Class A"])
five = Boxplot.prepare_data([[10, 20, 30, 40, 50, 60, 70]])
box.add_yaxis("Score", five)
space = Scatter3D().add("Points", [[1, 2, 3], [2, 4, 6]])
bars = Bar3D().add("Count", [[0, 0, 10], [1, 0, 20]],
    xaxis3d_opts=opts.Axis3DOpts(data=["A", "B"], type_="category"),
    yaxis3d_opts=opts.Axis3DOpts(data=["Mon"], type_="category"),
    zaxis3d_opts=opts.Axis3DOpts(type_="value"))
```

七项序列在该辅助函数下得到 `[10,20,40,60,70]`。Bar3D三元组的前两项是类目索引，最后是数量；Scatter3D三项均为点坐标。NumPy数据输出前可用 `.tolist()` 或显式转 `int/float`，避免特殊类型序列化问题。三维还需对应前端扩展，空白页先查依赖。

##### 小练习：五数能否直接当五个样本

已有五数 `[1,3,5,7,20]`，再送 `prepare_data` 是否稳妥？三维柱数据 `[1,0,20]` 在上例指什么？

**答案：** 不稳妥，会将摘要当原始样本再次计算分位数；应直接作为一个箱的数据。三维柱是B类、Mon、值20，不是数值坐标x=1元。

#### 桑基讲流向，漏斗讲阶段保留

pyecharts桑基图以 `nodes=[{"name":...}]` 定义节点，以 `links=[{"source":...,"target":...,"value":...}]` 定义有向流量。边值使用非负数量，方向由source和target指定，与Matplotlib正负flows不同。

```python
from pyecharts.charts import Sankey, Funnel
nodes = [{"name": n} for n in ["Income", "Cost", "Balance"]]
links = [{"source": "Income", "target": "Cost", "value": 60},
         {"source": "Income", "target": "Balance", "value": 40}]
flow = Sankey().add("Money", nodes, links)
funnel = Funnel().add("Users", [("Visit", 100), ("Cart", 60), ("Pay", 30)])
```

漏斗要用同一群体、同一观察期的有序阶段：支付/加购=30/60=50%，支付/访问=30/100=30%。这两个分母对应阶段转化率与整体转化率，不能混用；若业务步骤并非人数递减，应查统计口径，不为图形好看就篡改人数。课件示例按递减展示，实际任务应保留业务阶段顺序。

##### 小练习：修正桑基边与转化率

有人把pyecharts边写为Cost→Income，value=-60，又称30/60是整体支付率，错在哪？

**答案：** 正确为Income→Cost、value=60；方向由端点指定。整体支付率应30/100=30%，30/60只是在加购者中支付的比例。

#### 热力、词云、关系图依赖不同基础记录

热力图数据是 `[横类目索引,纵类目索引,值]`。横轴[A,B]、纵轴[Mon,Tue]时，`[1,0,20]` 是B在Mon的20，不是矩阵第1行第0列的通用写法；必须按本图轴定义解释。

```python
from pyecharts.charts import HeatMap, WordCloud, Graph
heat = (HeatMap().add_xaxis(["A", "B"])
        .add_yaxis("Count", ["Mon", "Tue"], [[0,0,10], [1,0,20]])
        .set_global_opts(visualmap_opts=opts.VisualMapOpts(min_=0, max_=20)))
cloud = WordCloud().add("Words", [("Python", 10), ("Plot", 6)])
graph = Graph().add("Links", [{"name": "A"}, {"name": "B"}],
                    [{"source": "A", "target": "B"}], layout="force")
```

词云输入是词和频次，事先要统一同义词与计数口径，字号不是精确比例尺。关系图节点代表实体，边代表定义好的联系；力导向布局只是根据连边安排位置，近不等于地理上近，也不证明因果。

##### 小练习：热力单元格和词云能否互换

数据是两门店×七天销量，要找周末高峰，应选什么？只有商品名称列表时能直接称“高频词云”吗？

**答案：** 用热力图并注明横纵轴和统一色标；词云需先统计频次，只有名称不能推出销量或频率，不能用随意字号代替实际计数。

### 本章小结

特殊图的共同入口是检查记录结构与统计含义：摘要不是样本，流向不是负值，索引不是实际数值，布局不是因果。

### 本章练习与检验

同一份销售表如何分别供给热力、桑基、词云？是否把同一行直接送入所有图？

**答案：** 不可。热力先按门店和日期聚合；桑基先定义来源与去向并汇总流量；词云先定义词项和计数（或明确金额权重）。每次转换都要保留单位与汇总校验。

## 四、从单图走向可阅读的分析页（7.11及后续主题与实战）

### 本章路线

本章要解决的问题：多图是叠加、分区、分页还是按时间播放？本章学完应会：区分overlap、Grid、Page和Timeline，并完成页面核验。

### 学习单元

> 题源：依课程课件7.11及课件主题、社区数据实战及配套示例自编变式；本节小练习和检验同源，数据均为教学示例。

#### 四种组合回答四种组织问题

| 组织方式 | 适用任务 | 需要检查 |
| --- | --- | --- |
| overlap | 同一坐标区叠加柱与线 | 类目顺序与轴单位 |
| Grid | 同页安排多个坐标区域 | 分区边界与配置对应 |
| Page | 将独立图放同一HTML页 | 总体阅读顺序 |
| Timeline | 相同结构随时间切换 | 每帧类目与尺度一致 |

`overlap` 是图表对象方法；不是单独导入一个Overlap类。下面Page先给比较图，再给趋势图；Timeline用固定类目显示两个月快照。代码自足，不依赖前文同名变量。

```python
from pyecharts.charts import Bar, Line, Page, Timeline, Grid
from pyecharts import options as opts
bar = Bar().add_xaxis(["A", "B"]).add_yaxis("Sales", [10, 20])
line = Line().add_xaxis(["A", "B"]).add_yaxis("Target", [12, 18])
bar.overlap(line)  # 本例两条系列单位相同
trend = Line().add_xaxis(["Apr", "May"]).add_yaxis("Total", [30, 40])
Page().add(bar, trend).render("report.html")
timeline = Timeline()
for month, values in [("Apr", [10,20]), ("May", [25,15])]:
    frame = (Bar().add_xaxis(["A", "B"]).add_yaxis("Sales", values)
             .set_global_opts(yaxis_opts=opts.AxisOpts(min_=0, max_=30)))
    timeline.add(frame, month)
timeline.render("timeline.html")
single = Bar().add_xaxis(["A", "B"]).add_yaxis("Sales", [10,20])
Grid().add(single, grid_opts=opts.GridOpts(pos_left="15%"))
```

Timeline两帧纵轴都为0到30，可直接看A从10升到25；若每帧自动缩放，柱子视觉高度可能误导。若叠加不同单位，先为第二个单位建立额外纵轴，再让该系列绑定相应 `yaxis_index`；仅写 `overlap` 不会自动创建正确双轴。

##### 小练习：选组合而不改变口径

需要“总览一页看三类指标”和“逐月看同一城市排名变化”，分别用什么？排名变化时类目顺序是否必须写清？

**答案：** 总览可用Page放独立图，固定分区可用Grid；逐月切换用Timeline。若按每月排名重新排序，必须让城市与数值成对重排，并让读者能识别城市迁移，不能只移动标签。

#### 主题服务读图，页面结论来自已核验指标

主题通过初始化配置传入，例如 `InitOpts(theme=ThemeType.LIGHT)`，需从 `pyecharts.globals` 导入ThemeType。深色主题并不自动适合打印，颜色仍要检查文字对比、图例辨识与色标单位。

课件社区实战可沿“问题→帖子/用户的统计单位→聚合→选图→页面结论”复习。假设3个帖子的回复数是10、20、30，平均20，帖子数3；若用户重复发帖，帖子数不等于独立用户数。把这类指标写到图标题或注释中，比堆满不同图类更有解释力。

输出后至少核对一处悬停值、图例开关、时间帧切换、长标签和资源加载。与Web框架集成时，框架负责页面和路由，图表仍依赖正确的数据配置与前端资源；本章无需为了绘图先搭建网站。

##### 小练习：主题切换后数字变了吗

切换主题后同一月份销售额由150变成180，可能仅由主题造成吗？应优先查什么？

**答案：** 单纯主题配置不应改数据。先查是否重新生成随机示例、换了数据版本、索引错位或复用了被修改的对象，再查浏览器是否仍加载旧文件。

### 本章小结

组合方式决定阅读路径，统一尺度与类目决定比较是否成立。最终应能从页面每个数字追溯到清晰的聚合口径。

### 本章练习与检验

HTML文件已生成，能否宣布可分享且离线可用？给出最小验收。

**答案：** 在浏览器实际打开，检查脚本加载和图形显示，抽查提示值、图例与Timeline切换；断网重新打开验证离线依赖。只有文件存在不够。

## 学习安排与阅读资料

必读：第七次课《第7章 pyecharts绘图》及配套PPT示例 notebook，依次核对7.1—7.11与后续主题、Web整合及社区数据实战。本文按数据结构归并图族，Web整合仅作概念边界，不要求部署服务。

[官方文档入口](https://pyecharts.org/) 与 [官方Boxplot实现](https://raw.githubusercontent.com/pyecharts/pyecharts/master/pyecharts/charts/basic_charts/boxplot.py)（核对日期2026-10-26）：后者用于核对prepare_data五数计算约定。正式运行应以课程已安装版本为准；不将master源码当作固定版本承诺。

## 本章综合习题测验

> 题源：依本章课件和前述教学内容自编综合题；全部数据为给定教学数据，非课程项目实测结果。先遮住解析独立作答。

### 第1题：纠正类别对应

**题目：** 类目["B","A"]、销量[20,50]，只排序类目再输出横向条形，A显示20。如何修复并核验？横向变换会自动修复吗？

**解析与答案：** 把成对记录一起排序为[("A",50),("B",20)]后拆成两列。横向变换仅改变朝向，不修复数据配对；悬停A应为50，核对B=20及总量70。

### 第2题：为构成选对分母

**题目：** 全店销售1000，TOP3为300、200、100，给Pie仅这三项。第一项显示几成？若想表达全店份额如何改？

**解析与答案：** 当前分母600，第一项50%；全店份额为30%。加入Other=400后共1000，或用条形并明确标全店百分比。TOP3内部结构与全店构成是两种问题。

### 第3题：区分三个三元组

**题目：** `[1,0,20]` 分别送入横轴[A,B]、纵轴[Mon,Tue]的HeatMap与Bar3D，再送入Scatter3D，含义分别是什么？若数据来自NumPy应检查什么？

**解析与答案：** 前两者为B、Mon的值20，HeatMap用颜色，Bar3D用高度；Scatter3D为实际点(1,0,20)。核对是否应按类目索引或数值解释，并转换为可序列化的Python标量列表，不能只因三元组长度相同就通用。

### 第4题：检查流向与转化

**题目：** 访问200、加购80、支付40；资金收入100，流向成本60、结余40。分别给阶段支付率、整体支付率和pyecharts桑基边写法。

**解析与答案：** 支付/加购=40/80=50%；支付/访问=40/200=20%。边为Income→Cost值60、Income→Balance值40，均为非负值。漏斗的分母来自同群体阶段，桑基的方向来自source/target。

### 第5题：审查交互月报

**题目：** 两个月图自动缩放后柱都一样高；双轴销售与设备数相交；断网后HTML空白。哪些结论或交付尚不成立，怎样处理？

**解析与答案：** 相同柱高不能证明金额相同，应统一轴范围并读提示值；双轴交点不等于数值相等或因果，需分清轴与单位；空白说明离线依赖未齐，查运行库和资源路径。修正后逐项打开、悬停、切帧并断网复核。

## 公式卡

- 部分占比=部分数值÷所选总体总值；TOP子集的总值不等于全体总值。
- 阶段转化率=后阶段人数÷前阶段人数；整体转化率=末阶段人数÷起始人数，要求同群体、同观察期。
- 同单位可加系列的堆叠高度=各系列值之和；不同单位不能相加。
