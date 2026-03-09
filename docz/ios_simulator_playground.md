# 在 iOS 模拟器上运行 Midscene Playground 的详细步骤

在 macOS 上，你可以通过 Xcode 附带的 iOS 模拟器配合 Midscene Playground 进行纯视觉的自动化测试体验。以下是详细的从零基础到启动 Playground 的执行步骤。

---

## 🛠️ 第一步：环境准备

1. **安装 Xcode 及命令行工具**
   - 从 Mac App Store 下载并安装 [Xcode](https://apps.apple.com/us/app/xcode/id497799835?mt=12)。
   - 安装完成后，打开终端执行以下命令安装命令行工具（如果已安装会提示）：
     ```bash
     xcode-select --install
     ```

2. **启动一个 iOS 模拟器**
   - 打开 Xcode，在顶部菜单栏选择 **Xcode** -> **Open Developer Tool** -> **Simulator**。
   - 这会启动一个默认的 iOS 模拟器（例如 iPhone 15）。确保模拟器开机并停留在桌面。
   - 你可以通过终端运行 `xcrun simctl list devices` 确认模拟器状态为 `Booted`。

---

## ⚙️ 第二步：准备 WebDriverAgent (WDA)

Midscene 的底层依赖 WDA 来捕获屏幕和执行点击事件。

1. **找一个空目录安装 WDA 依赖**
   在终端中执行：
   ```bash
   mkdir midscene-ios-test && cd midscene-ios-test
   npm init -y
   npm install appium-webdriveragent
   ```

2. **为模拟器编译并运行 WDA**
   继续在终端中执行以下命令（注意将 `iPhone 15` 替换为你实际启动的模拟器型号）：
   ```bash
   cd node_modules/appium-webdriveragent
   
   xcodebuild -project WebDriverAgent.xcodeproj \
             -scheme WebDriverAgentRunner \
             -destination 'platform=iOS Simulator,name=iPhone 15' \
             test
   ```
   *注意：如果编译成功，终端最后会卡住在 `ServerURLHere->http://127.0.0.1:8100<-ServerURLHere` 类似的输出，这说明 WDA 已经在模拟器后台成功运行，**请保持这个终端窗口不要关闭**。*

---

## 🚀 第三步：启动 Midscene Playground

重新打开一个**新的终端窗口**，直接运行以下命令启动 Midscene 的前端调试面板：

```bash
# 无需克隆庞大的代码库，直接使用 npx 运行云端最新包
npx @midscene/ios
```
*(或者使用 `npx @midscene/playground` 可以在后续界面中选择接入 iOS)*

1. **终端输出提示**：
   命令执行后，终端会提示类似 `Server running at http://localhost:3000`。
2. **打开浏览器**：
   在浏览器中访问 `http://localhost:3000`。
3. **连接并自动投屏**：
   - Playground 前端界面加载后，会自动检测连接到本地 `8100` 端口的 WDA 服务。
   - 连接成功后，界面的左侧将实时映射出你 iOS 模拟器的画面。
4. **开始测试大模型视觉控制**：
   - 点击界面上的设置齿轮，配置你的多模态大模型 API Key（例如 OpenAI GPT-4o 或 Qwen-VL）。
   - 在右侧的输入框中输入自然语言（例如：“点击日历 App”、“在搜索框输入苹果”），点击执行，就可以看到左侧的模拟器被 AI 自动操控了！

---

## 🤖 自动化执行脚本记录 (附加信息)

如果在本地执行以上步骤遇到问题，可以参考下述由 AI 发起的自动化执行步骤记录：

1. **环境依赖检查**：检查并尝试安装了 macOS 必备的 `xcode-select` 命令行工具。
2. **侦测设备资源**：通过 `xcrun simctl list devices` 扫描本地安装的的所有单可用 iOS 模拟器镜像。
3. **开机与唤醒界面**：通过 `xcrun simctl boot` 命令在后台将该模拟器开机，并唤起了 `Simulator` 可视化窗口程序。
4. **准备驱动中间件**：在用户目录下创建了 `~/midscene-ios-test` 文件夹，并安装了 iOS 自动化的核心底层依赖 `appium-webdriveragent`。
5. **首次编译与部署 WDA**：进入依赖包目录，触发了 `xcodebuild` 命令，正式向刚开机的模拟器编译安装并启动 WebDriverAgentRunner 测试服务（用于在底层接管操作和截取屏幕像素）。
6. **故障恢复与重试**：在此期间 WDA 服务曾意外闪退导致端口 `8100` 无法连通，系统进行了静默捕获，并为你重新运行了一次 `xcodebuild` 保证底层服务的稳定在线。
7. **启动可视化控制台**：最后，在代码库外运行了 `npx -y @midscene/ios-playground` 命令，成功桥接上了刚才跑好的底层控制服务，并对外暴露出了 `http://localhost:5800` 这个可通过浏览器访问的自然语言大模型调试台。
