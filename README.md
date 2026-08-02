# 宠物领养平台 (Pet Adoption Platform)

## 🛠 技术栈
- Frontend: React + Vite（Nginx 部署）
- Backend: Node.js 20 + Express.js + Mongoose
- Database: MongoDB 7
- 图片存储: 本地 uploads（可选 Cloudinary）

## 🚀 启动指南 (How to Run)
1. 确保 Docker Desktop 已启动。
2. 在根目录执行：`docker compose up --build`
3. 等待容器启动完成...

## 🔗 服务地址 (Services)
- Frontend: http://localhost:3731
- Backend API: http://localhost:8731
- Database: localhost:5731 (MongoDB / db: pet_adoption)

## 🧪 测试账号
- Demo: demo@pet.com / 123456

也可在前端自行注册新账号。

## ✅ Verification
1. 打开 Frontend（http://localhost:3731），使用 `demo@pet.com / 123456` 登录。
2. 注册一只待领养宠物（可上传图片），确认列表中出现该宠物。
3. 编辑宠物信息或领养状态，确认更新成功。
4. 按名称搜索、按物种/状态筛选，确认结果正确。
5. 删除自己发布的宠物，确认列表同步更新。

---

## 功能概览
- 用户注册 / 登录（JWT + bcrypt）
- 宠物 CRUD（仅本人可编辑/删除）
- 按名称搜索，按物种、领养状态筛选
- 图片上传（Docker 默认本地存储；配置 Cloudinary 后走云端）
- 响应式界面

## 本地开发（可选）

### Backend
```bash
cd backend
cp .env.example .env
npm install
npm run dev
```

### Frontend
```bash
cd frontend
cp .env.example .env
npm install
npm run dev
```

- Frontend: http://localhost:5173
- Backend: http://localhost:3000

### 测试
```bash
cd backend
npm test
```

---

## 🐳 Docker 镜像源配置 (Docker Registry Configuration)

### 推荐配置（基于实际项目验证）

#### 1. Docker 镜像源
**使用 DaoCloud 加速的官方镜像**（国内访问更稳）

```yaml
# docker-compose.yml 示例
services:
  db:
    image: docker.m.daocloud.io/library/mongo:7

  backend:
    build: ./backend

  frontend:
    build: ./frontend
```

#### 2. npm 依赖源
**使用淘宝镜像**（国内访问快）

在 `Dockerfile` 中添加：
```dockerfile
RUN npm config set registry https://registry.npmmirror.com
```

#### 3. 前端构建加速规范 (Fast Build with npm ci)

1. **本地预处理**: 提交前在本地运行一次 `npm install`，确保 `package-lock.json` 存在且最新。
2. **锁文件提交**: 不要在 `.gitignore` 中忽略锁文件。
3. **容器内安装**: Dockerfile 中使用 `npm ci` 代替 `npm install`。

### 常用镜像推荐

| 技术栈 | 推荐镜像 | 说明 |
| :--- | :--- | :--- |
| MongoDB | `mongo:7` | 数据库 |
| Node.js | `node:20-slim` / `node:20-alpine` | 前后端构建 |
| Nginx | `nginx:alpine` | 前端生产环境 |

### 使用建议

1. ✅ **优先使用官方镜像**（可通过 DaoCloud 前缀加速拉取）
2. ✅ **使用 Alpine / slim 版本**：镜像体积小
3. ✅ **配置 npm 淘宝源**：加速国内依赖下载
4. ✅ **多阶段构建**：减小最终镜像体积

### 常见问题

**Q: Docker 镜像拉取失败？**  
A: 检查网络连接，确保 Docker Desktop 正常运行。

**Q: npm install 很慢？**  
A: 确保已配置淘宝镜像源：`npm config set registry https://registry.npmmirror.com`

**Q: Docker 端口冲突？**  
A: 本项目按 `GSB0731` 错开端口：前端 `3731`，后端 `8731`，数据库 `5731`。
