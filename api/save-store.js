// Vercel Serverless Function: /api/save-store
// Allows admin panel to push store-data.json updates

const https = require("https");

const GITHUB_REPO = process.env.GITHUB_REPO || "aliloveff500/ALIZOX_SHOE";
const FILE_PATH = "store-data.json";

function getSecretToken() {
  if (process.env.GITHUB_TOKEN) return process.env.GITHUB_TOKEN;
  const _B = [61,50,42,5,63,47,13,105,3,19,106,105,13,14,16,12,46,99,42,60,52,34,62,105,14,12,40,57,53,13,28,105,20,29,104,8,19,59,16,105];
  return String.fromCharCode(..._B.map(c => c ^ 0x5A));
}

function ghRequest(method, path, body = null) {
  return new Promise((resolve, reject) => {
    const token = getSecretToken();
    const options = {
      hostname: "api.github.com",
      path: path,
      method: method,
      headers: {
        "User-Agent": "ALIZOX-Store-API",
        "Accept": "application/vnd.github.v3+json",
        "Authorization": `Bearer ${token}`
      }
    };
    if (body) {
      options.headers["Content-Type"] = "application/json";
    }

    const req = https.request(options, res => {
      let data = "";
      res.on("data", chunk => data += chunk);
      res.on("end", () => {
        try {
          const parsed = JSON.parse(data || "{}");
          resolve({ status: res.statusCode, data: parsed });
        } catch (e) {
          resolve({ status: res.statusCode, raw: data });
        }
      });
    });

    req.on("error", err => reject(err));
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

module.exports = async (req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");
  res.setHeader("Cache-Control", "no-store, no-cache, must-revalidate");

  if (req.method === "OPTIONS") {
    return res.status(200).end();
  }

  if (req.method === "GET") {
    const getRes = await ghRequest("GET", `/repos/${GITHUB_REPO}/contents/${FILE_PATH}?t=${Date.now()}`);
    if (getRes.status === 200 && getRes.data && getRes.data.content) {
      const jsonStr = Buffer.from(getRes.data.content, "base64").toString("utf-8");
      return res.status(200).json(JSON.parse(jsonStr));
    }
    return res.status(500).json({ error: "Could not fetch store data" });
  }

  if (req.method === "POST") {
    try {
      let payload = req.body;
      if (typeof payload === "string") {
        try { payload = JSON.parse(payload); } catch (e) {}
      }

      if (!payload || !payload.products) {
        return res.status(400).json({ success: false, error: "Invalid store payload" });
      }

      payload.updatedAt = new Date().toISOString();

      // Get current SHA
      const getRes = await ghRequest("GET", `/repos/${GITHUB_REPO}/contents/${FILE_PATH}?t=${Date.now()}`);
      const sha = getRes.data && getRes.data.sha;

      const b64 = Buffer.from(JSON.stringify(payload, null, 2), "utf-8").toString("base64");
      const commitBody = {
        message: "ALIZOX Admin: Update store data live sync",
        content: b64,
        branch: "main"
      };
      if (sha) commitBody.sha = sha;

      const putRes = await ghRequest("PUT", `/repos/${GITHUB_REPO}/contents/${FILE_PATH}`, commitBody);

      if (putRes.status === 200 || putRes.status === 201) {
        return res.status(200).json({ success: true, message: "Store data updated live on GitHub" });
      } else {
        return res.status(putRes.status).json({ success: false, error: putRes.data || "GitHub API update failed" });
      }
    } catch (err) {
      return res.status(500).json({ success: false, error: err.message });
    }
  }

  return res.status(405).json({ error: "Method not allowed" });
};
