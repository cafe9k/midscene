# Midscene iOS 自动化架构详解

## 整体架构图

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Midscene iOS Playground                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌──────────────┐     ┌──────────────────┐     ┌──────────────────────┐  │
│  │   User      │     │   IOSAgent        │     │   AI Model           │  │
│  │   Code      │────▶│   (PageAgent)     │────▶│   (GLM/Qwen/GPT)    │  │
│  │             │     │                  │     │                      │  │
│  └──────────────┘     └──────────────────┘     └──────────────────────┘  │
│                                │                                            │
│                                ▼                                            │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │                         TaskExecutor                                 │  │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │  │
│  │  │  Planning       │  │  ActionSpace    │  │  TaskBuilder    │  │  │
│  │  │  (plan/llm)    │  │  (设备动作)     │  │  (执行计划)    │  │  │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘  │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                │                                            │
│                                ▼                                            │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │                      IOSDevice (AbstractInterface)                  │  │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │  │
│  │  │  ActionSpace   │  │  WebDriver     │  │  Screenshot     │  │  │
│  │  │  (Tap/Input/  │  │  Agent Client  │  │  Capture        │  │  │
│  │  │   Scroll...)   │  │                │  │                 │  │  │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘  │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                │                                            │
│                                ▼                                            │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │                    WebDriverAgent (WDA)                             │  │
│  │         (Appium WebDriverAgent - iOS 设备控制层)                    │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                │                                            │
│                                ▼                                            │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │                         iOS Device                                   │  │
│  │                    (真机 / 模拟器)                                   │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 核心概念详解

### 1. AbstractInterface (设备抽象层)

**文件位置**: `packages/core/src/device/index.ts`

```typescript
export abstract class AbstractInterface {
  abstract interfaceType: string;
  abstract screenshotBase64(): Promise<string>;
  abstract size(): Promise<Size>;
  abstract actionSpace(): DeviceAction[];  // 关键：定义可用动作
}
```

**作用**：统一不同平台（iOS/Android/Web）的接口抽象

### 2. ActionSpace (动作空间)

**文件位置**: `packages/ios/src/device.ts`

ActionSpace 定义了设备支持的所有可执行动作：

```typescript
actionSpace(): DeviceAction<any>[] {
  const defaultActions = [
    defineActionTap(...),           // 点击
    defineActionDoubleClick(...),   // 双击
    defineActionScroll(...),        // 滚动
    defineActionSwipe(...),         // 滑动
    defineActionInput(...),         // 输入文本
    defineActionKeyboardPress(...), // 键盘按键
    defineActionDragAndDrop(...),  // 拖拽
    defineActionCursorMove(...),   // 光标移动
    defineActionLongPress(...),   // 长按
    // iOS 特有动作
    defineActionLaunch(...),       // 启动应用
    defineActionTerminate(...),    // 终止应用
    defineActionIOSHomeButton(...),// Home 键
    defineActionIOSAppSwitcher(...),// 应用切换器
    defineActionRunWdaRequest(...), // WDA 请求
  ];
  return defaultActions;
}
```

#### Action 定义结构

```
DeviceAction<T> {
  name: string;           // 动作名称，如 "Tap", "Input", "Scroll"
  description: string;    // 动作描述（供 AI 理解）
  paramSchema: ZodSchema; // 参数校验 Schema
  sample: object;         // 示例参数
  interfaceAlias?: string;// 接口别名
  call: Function;         // 实际执行函数
}
```

#### 常用 Action 类型

| Action 名称 | 描述 | 参数 |
|-------------|------|------|
| `Tap` | 点击元素 | `locate: LocateResult` |
| `DoubleClick` | 双击元素 | `locate: LocateResult` |
| `Input` | 输入文本 | `value: string, locate: LocateResult, mode: replace/clear/typeOnly` |
| `Scroll` | 滚动屏幕 | `direction: up/down/left/right, distance?: number` |
| `Swipe` | 滑动操作 | `startPoint, endPoint, duration` |
| `LongPress` | 长按操作 | `locate: LocateResult, duration: number` |
| `DragAndDrop` | 拖拽 | `from: LocateResult, to: LocateResult` |
| `KeyboardPress` | 键盘按键 | `keyName: string` |
| `Launch` | 启动应用 | `bundleId: string` |
| `Terminate` | 终止应用 | `bundleId: string` |

### 3. TaskExecutor (任务执行器)

**文件位置**: `packages/core/src/agent/tasks.ts`

TaskExecutor 是整个自动化流程的核心编排器：

```typescript
export class TaskExecutor {
  interface: AbstractInterface;        // 设备接口
  service: Service;                   // AI 服务
  providedActionSpace: DeviceAction[]; // 动作空间
  taskBuilder: TaskBuilder;            // 任务构建器
  conversationHistory: ConversationHistory; // 对话历史

  // 核心方法
  async runPlans(plans: PlanningAction[]): Promise<ExecutionResult>
  async aiAct(task: string): Promise<ExecutionResult>
  async waitFor(assertion: string): Promise<ExecutionResult>
  async extract(query: string): Promise<any>
}
```

### 4. Planning (规划阶段)

Planning 是 AI 理解用户任务并生成执行计划的过程：

```
User Task ──▶ AI Model (LLM) ──▶ PlanningAction[]
      │                              │
      │                              ▼
      │                     ┌─────────────────┐
      │                     │  解析 XML/JSON  │
      │                     │  提取动作和参数  │
      │                     └─────────────────┘
      │                              │
      ▼                              ▼
┌─────────────────────────────────────────────────────┐
│              PlanningAction 结构                     │
│  { type: "Tap", param: { locate: {...} } }       │
│  { type: "Input", param: { value: "text" } }     │
│  { type: "Scroll", param: { direction: "down" }  │
└─────────────────────────────────────────────────────┘
```

#### Planning 流程

1. **截图获取**: 调用 `device.screenshotBase64()` 获取当前屏幕
2. **DOM 树提取**: 调用 `descriptionOfTree()` 生成 UI 描述
3. **构建 Prompt**: 将用户任务、截图、DOM 树、ActionSpace 组合成 prompt
4. **调用 AI**: 将 prompt 发送给 AI 模型
5. **解析响应**: 解析 AI 返回的 XML/JSON，获取执行计划

### 5. TaskBuilder (任务构建)

**文件位置**: `packages/core/src/agent/task-builder.ts`

TaskBuilder 负责将 PlanningAction 转换为可执行的 ExecutionTask：

```typescript
export class TaskBuilder {
  async build(plans: PlanningAction[]) {
    const planHandlers = new Map([
      ['Locate', handleLocatePlan],    // 定位元素
      ['Tap', handleActionPlan],      // 执行动作
      ['Input', handleActionPlan],
      ['Scroll', handleActionPlan],
      // ...
    ]);
  }
}
```

### 6. IOSDevice (iOS 设备实现)

**文件位置**: `packages/ios/src/device.ts`

IOSDevice 实现了 AbstractInterface，并封装了与 WDA 的通信：

```typescript
export class IOSDevice implements AbstractInterface {
  interfaceType: InterfaceType = 'ios';
  private wdaBackend: WebDriverAgentBackend;
  private wdaManager: WDAManager;

  // 截图
  async screenshotBase64(): Promise<string>

  // 屏幕尺寸
  async size(): Promise<Size>

  // 可用动作
  actionSpace(): DeviceAction[]

  // 设备操作
  async mouseClick(x: number, y: number): Promise<void>
  async typeText(text: string): Promise<void>
  async swipe(x1, y1, x2, y2, duration): Promise<void>
  async scrollDown(distance?, startingPoint?): Promise<void>
  // ...
}
```

### 7. IOSAgent (iOS Agent 封装)

**文件位置**: `packages/ios/src/agent.ts`

IOSAgent 继承自 PageAgent，提供了类型安全的动作调用：

```typescript
export class IOSAgent extends PageAgent<IOSDevice> {
  // 类型安全的动作封装
  launch!: WrappedAction<DeviceActionLaunch>;
  terminate!: WrappedAction<DeviceActionTerminate>;
  home!: WrappedAction<DeviceActionIOSHomeButton>;
  appSwitcher!: WrappedAction<DeviceActionIOSAppSwitcher>;

  // 通用 AI 动作
  async aiAct(task: string): Promise<ExecutionResult>
  async aiAssert(task: string, opts?: AgentAssertOpt): Promise<void>
  async waitFor(assertion: string, opts?: AgentWaitForOpt): Promise<void>
  async extract(query: string): Promise<any>
}
```

## 执行流程图

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         用户调用 aiAct()                                │
└─────────────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                      1. 截图获取 (UIContext)                          │
│  ┌───────────────────┐    ┌───────────────────┐                       │
│  │ device.screenshot │───▶│ 提取 DOM 树      │                       │
│  │ Base64 图像       │    │ (descriptionOfTree)                      │
│  └───────────────────┘    └───────────────────┘                       │
└─────────────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                      2. Planning 阶段                                  │
│  ┌─────────────────────────────────────────────────────────────────┐  │
│  │  callAI({ systemPrompt, userPrompt + screenshot })           │  │
│  │                                                                  │  │
│  │  System Prompt 包含:                                            │  │
│  │  - ActionSpace (可用动作列表)                                    │  │
│  │  - 任务要求                                                      │  │
│  │  - 输出格式 (XML/JSON)                                          │  │
│  └─────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                      3. AI 响应解析                                    │
│  ┌───────────────────┐    ┌───────────────────┐                       │
│  │ parseXMLResponse  │───▶│ PlanningAction[]  │                       │
│  │                   │    │ - type: "Tap"      │                       │
│  │                   │    │ - param: {...}    │                       │
│  └───────────────────┘    └───────────────────┘                       │
└─────────────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                      4. 验证 ActionSpace                               │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │ actionSpace.find(action => action.name === plan.type)       │   │
│  │                                                              │   │
│  │ ⚠️ 关键验证: 检查 AI 返回的动作是否在 ActionSpace 中定义   │   │
│  │    如果不在，会抛出 "Action type 'XXX' not found" 错误      │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                      5. TaskBuilder 构建执行任务                        │
│                                                                  │
│  ┌───────────────────┐    ┌───────────────────┐                   │
│  │ handleLocatePlan  │    │ handleActionPlan  │                   │
│  │ - 调用 AI 定位元素 │    │ - 执行设备动作     │                   │
│  │ - 返回 LocateResult│    │ - Tap/Input/Scroll│                   │
│  └───────────────────┘    └───────────────────┘                   │
└─────────────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                      6. IOSDevice 执行动作                             │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │ WDA Client                                                │   │
│  │ ┌───────────┐  ┌───────────┐  ┌───────────┐               │   │
│  │ │ tap(x,y)  │  │ type(text)│  │ swipe()   │  ──▶ WDA    │   │
│  │ └───────────┘  └───────────┘  └───────────┘  ──▶ iOS Device│   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                      7. 返回执行结果                                     │
│               ExecutionResult { output, thought, runner }             │
└─────────────────────────────────────────────────────────────────────────┘
```

## 环境配置

### 常用模型配置

#### Qwen3-VL-Plus

```bash
MIDSCENE_MODEL_API_KEY=your-api-key
MIDSCENE_MODEL_NAME=qwen3-vl-plus
MIDSCENE_MODEL_BASE_URL=https://dashscope.aliyuncs.com/api/v1
MIDSCENE_MODEL_FAMILY=qwen3-vl
```

#### GLM-4V-Plus

```bash
MIDSCENE_MODEL_API_KEY=your-api-key
MIDSCENE_MODEL_NAME=glm-4v-plus
MIDSCENE_MODEL_BASE_URL=https://open.bigmodel.cn/api/paas/v4/
MIDSCENE_MODEL_FAMILY=glm-v
```

#### GPT-4o

```bash
MIDSCENE_MODEL_API_KEY=sk-...
MIDSCENE_MODEL_NAME=gpt-4o
MIDSCENE_MODEL_BASE_URL=https://api.openai.com/v1
MIDSCENE_MODEL_FAMILY=openai
```

### MIDSCENE_MODEL_FAMILY 作用

`MIDSCENE_MODEL_FAMILY` 是 Midscene 的核心配置，用于指定使用的视觉语言模型系列：

| 模型家族 | 推理配置参数 |
|----------|-------------|
| `qwen3-vl`, `qwen3.5` | `enable_thinking`, `thinking_budget` |
| `doubao-vision`, `doubao-seed` | `thinking.type`, `thinking.budget` |
| `glm-v` | `thinking.type` |
| `gpt-5` | `reasoning.effort` |

## 常见错误与解决方案

### Error: Action type 'XXX' not found

**原因**：AI 模型在 Planning 阶段返回了一个不在 ActionSpace 中定义的动作。

**解决方案**：
1. 确保 `MIDSCENE_MODEL_FAMILY` 设置正确
2. 在 system prompt 中强调只能使用定义的 ActionSpace
3. 检查模型输出是否越界

### Error: MIDSCENE_MODEL_FAMILY is not set

**原因**：未设置 `MIDSCENE_MODEL_FAMILY` 环境变量。

**解决方案**：设置对应的 `MIDSCENE_MODEL_FAMILY` 值。

## 使用示例

```typescript
import { agentFromWebDriverAgent } from '@midscene/ios/agent';

// 创建 Agent
const agent = await agentFromWebDriverAgent({
  uri: 'http://localhost:8100',
});

// AI 动作
const result = await agent.aiAct('点击登录按钮');

// 断言
await agent.aiAssert('登录成功，跳转到首页');

// 等待
await agent.aiWaitFor('出现加载完成的提示');

// 提取信息
const username = await agent.extract('当前登录用户的用户名');

// iOS 特有操作
await agent.launch('com.apple.Preferences');
await agent.home();
await agent.terminate('com.example.app');
```

## 相关文件

| 文件路径 | 描述 |
|----------|------|
| `packages/ios/src/device.ts` | IOSDevice 实现 |
| `packages/ios/src/agent.ts` | IOSAgent 实现 |
| `packages/core/src/agent/tasks.ts` | TaskExecutor 实现 |
| `packages/core/src/agent/task-builder.ts` | TaskBuilder 实现 |
| `packages/core/src/agent/agent.ts` | PageAgent 基类 |
| `packages/core/src/device/index.ts` | AbstractInterface 定义 |
| `packages/core/src/ai-model/llm-planning.ts` | Planning 实现 |
