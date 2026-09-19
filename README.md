# Spark_vLLM

使用 Docker Compose 在 NVIDIA DGX Spark 上部署 [vLLM](https://github.com/vllm-project/vllm) 推論服務，並透過 [LiteLLM](https://github.com/BerriAI/litellm) 提供統一的 OpenAI 相容 API 入口（含 API Key 管理與管理介面）。

目前提供的模型：

| 模型 | 對外模型名稱 |
| --- | --- |
| [nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4](https://huggingface.co/nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4) | `nemotron-3.5-lightning` |
| [openai/gpt-oss-120b](https://huggingface.co/openai/gpt-oss-120b) | `gpt-oss-120b` |

## 架構

```
                         ┌─► nemotron-lightning (vLLM)
client ──► LiteLLM :4000 ┤
           (API Key)     └─► gpt-oss            (vLLM)
               │
               └─► litellm-db (PostgreSQL)
```

| 服務 | 容器名稱 | 對外埠 | 說明 |
| --- | --- | --- | --- |
| `nemotron-lightning` | `vllm-nemotron-lightning` | 8000 | vLLM 服務 Nemotron 3.5 Lightning，context 長度 131072，GPU 記憶體使用率 0.3 |
| `gpt-oss` | `vllm-gpt-oss` | 8001 | vLLM 服務 gpt-oss-120b（MXFP4 量化、FP8 KV cache），GPU 記憶體使用率 0.5 |
| `litellm-db` | `litellm-db` | 不對外 | PostgreSQL 16，儲存 LiteLLM 的 API Key 與使用紀錄，資料存在 volume `litellm-db-data` |
| `litellm` | `litellm-router` | 4000 | LiteLLM Proxy：統一入口，依模型名稱將請求轉送給對應的 vLLM 服務，並提供管理介面 |

## 專案結構

```
.
├── .env.example              # 環境變數範本（複製為 .env 使用）
├── run.sh                    # 啟動腳本：先 down 再 up -d
└── docker/
    ├── docker-compose.yml    # 服務定義（vLLM x2、LiteLLM、PostgreSQL）
    └── litellm_config.yaml   # LiteLLM 的模型路由設定
```

## 前置需求

- NVIDIA DGX Spark（本專案的目標硬體）
- Docker Engine 與 Docker Compose v2（`docker compose` 指令）
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)，讓容器可以使用 GPU
- Hugging Face 帳號與 [Access Token](https://huggingface.co/settings/tokens)；若模型需要授權（gated），請先在模型頁面同意使用條款
- 足夠的磁碟空間存放模型檔案（數十 GB 等級）

## 快速開始

**1. 取得專案**

```bash
git clone https://github.com/Prisvalis/Spark_vLLM.git
cd Spark_vLLM
```

**2. 建立 `.env`**

```bash
cp .env.example .env
nano .env    # 填入實際的 Token、密碼與金鑰
```

各變數的意義請見下方[環境變數](#環境變數)。`.env` 已列入 `.gitignore`，不會被提交。

**3. 啟動**

```bash
./run.sh
```

`run.sh` 會依序執行：

1. 載入 `.env`
2. `docker compose down`：停止並移除既有容器（資料 volume 會保留）
3. `docker compose up -d`：在背景啟動所有服務

> 請在專案根目錄執行，`run.sh` 內的 `.env` 與 `docker/docker-compose.yml` 都是相對路徑。

**4. 確認狀態**

```bash
docker compose -f docker/docker-compose.yml --env-file .env ps
docker compose -f docker/docker-compose.yml --env-file .env logs -f gpt-oss
```

第一次啟動時，vLLM 需要先下載模型再載入 GPU，可能要花數分鐘甚至更久。log 出現 `Application startup complete` 就表示該服務已可使用。

## 環境變數

| 變數 | 必填 | 說明 |
| --- | --- | --- |
| `HF_TOKEN` | ✅ | Hugging Face Access Token，vLLM 下載模型時使用 |
| `LITELLM_MASTER_KEY` | ✅ | LiteLLM 管理員金鑰，必須以 `sk-` 開頭；呼叫 LiteLLM API 與建立其他 Key 時使用 |
| `LITELLM_DB_PASSWORD` | ✅ | PostgreSQL 密碼；會被組進連線字串，請避免使用空白及 `@ : / ? # % $` 等特殊字元 |
| `LITELLM_UI_USERNAME` | ✅ | LiteLLM 管理介面登入帳號 |
| `LITELLM_UI_PASSWORD` | ✅ | LiteLLM 管理介面登入密碼 |
| `HF_CACHE_DIR` | 選填 | 主機上的 Hugging Face 模型快取目錄（絕對路徑，指到 `huggingface/hub` 這一層）；未設定時自動使用執行者的 `$HOME/.cache/huggingface/hub`，見[調整設定](#調整設定) |

`.env.example` 中的值只是佔位文字，請把必填的變數全部換成實際的值。

## 使用方式

### 透過 LiteLLM（建議的入口）

所有請求都帶上 API Key（`LITELLM_MASTER_KEY` 或在管理介面建立的 Key），`model` 填上方表格中的對外模型名稱。

列出可用模型：

```bash
curl http://localhost:4000/v1/models \
  -H "Authorization: Bearer sk-your-master-key"
```

Chat Completions：

```bash
curl http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer sk-your-master-key" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-oss-120b",
    "messages": [{"role": "user", "content": "你好，請簡單自我介紹"}]
  }'
```

使用 OpenAI Python SDK：

```python
from openai import OpenAI

client = OpenAI(base_url="http://<主機 IP>:4000/v1", api_key="sk-your-master-key")

resp = client.chat.completions.create(
    model="nemotron-3.5-lightning",
    messages=[{"role": "user", "content": "你好，請簡單自我介紹"}],
)
print(resp.choices[0].message.content)
```

### LiteLLM 管理介面

瀏覽器開啟 `http://<主機 IP>:4000/ui`，以 `LITELLM_UI_USERNAME` / `LITELLM_UI_PASSWORD` 登入，可以建立與管理 API Key、查看用量等。

### 直接連 vLLM（除錯用）

不經過 LiteLLM，直接呼叫個別的 vLLM 服務，不需要 API Key：

```bash
curl http://localhost:8000/v1/models   # nemotron-3.5-lightning
curl http://localhost:8001/v1/models   # gpt-oss-120b
```

## 常用指令

以下指令皆在專案根目錄執行：

```bash
# 查看服務狀態
docker compose -f docker/docker-compose.yml --env-file .env ps

# 追蹤某個服務的 log（nemotron-lightning / gpt-oss / litellm / litellm-db）
docker compose -f docker/docker-compose.yml --env-file .env logs -f <服務名稱>

# 只重啟單一服務（不必重載另一個模型）
docker compose -f docker/docker-compose.yml --env-file .env restart litellm

# 停止並移除所有容器（保留資料 volume）
docker compose -f docker/docker-compose.yml --env-file .env down
```

## 調整設定

- **新增或更換模型**：在 `docker/docker-compose.yml` 新增或修改對應的 vLLM 服務，並在 `docker/litellm_config.yaml` 的 `model_list` 加上路由。`model` 欄位中 `hosted_vllm/` 後面的名稱要與 vLLM 的 `--served-model-name` 一致，`api_base` 使用 compose 服務名稱與容器內埠號（例如 `http://gpt-oss:8000/v1`）。
- **修改 `litellm_config.yaml` 後**：需要重啟 LiteLLM 才會生效（`restart litellm`）。
- **GPU 記憶體**：兩個 vLLM 服務共用同一顆 GPU，`--gpu-memory-utilization` 的總和不可超過 1.0（目前是 0.3 + 0.5）。DGX Spark 的 CPU 與 GPU 共用 128 GB 統一記憶體，作業系統與其他程式也會用到，調高時請保留餘裕。
- **Hugging Face 快取路徑**：預設使用執行者家目錄下的 `$HOME/.cache/huggingface/hub`，並掛載到容器內的 `/root/.cache/huggingface/hub`，下載過的模型不會重複下載，一般不需要設定。如果模型放在其他位置（例如外接硬碟），在 `.env` 加上 `HF_CACHE_DIR="/path/to/huggingface/hub"` 即可，不需要修改 `docker-compose.yml`。

## 注意事項

- **修改 `LITELLM_DB_PASSWORD` 後 LiteLLM 連不上資料庫**：PostgreSQL 只會在資料 volume 第一次建立時套用密碼，之後改 `.env` 不會改到資料庫內的密碼。二選一處理：
  - 保留資料：`docker exec -it litellm-db psql -U litellm -c "ALTER USER litellm PASSWORD '新密碼';"`，再重啟 `litellm`
  - 資料可丟棄：`docker compose -f docker/docker-compose.yml --env-file .env down -v`（**會刪除所有 LiteLLM 資料，包含已建立的 API Key**）
- **vLLM 的 8000 / 8001 埠沒有 API Key 保護**：能連到這台主機的人都可以直接呼叫。建議用防火牆限制來源，對外只開放 LiteLLM 的 4000 埠。
- **LiteLLM 不會等 vLLM 就緒**：`./run.sh` 執行完只代表容器已啟動；在 vLLM 載入完模型前，經由 LiteLLM 呼叫該模型會失敗，請先用 `logs` 確認。
- **主機重開機後會自動啟動**：所有服務都設定了 `restart: unless-stopped`，除非你手動 `down` 或 `stop`。
- **不要用 `sudo` 執行 `./run.sh`**：`sudo` 下的 `$HOME` 可能變成 `/root`，快取路徑會跟著改變，已下載的模型會被重新下載。建議把使用者加入 `docker` 群組後直接執行；若一定要用 `sudo`，請在 `.env` 明確設定 `HF_CACHE_DIR`。
- **啟動時出現 `The "..." variable is not set` 警告**：代表 `.env` 缺少該變數，請對照上方[環境變數](#環境變數)補齊。
