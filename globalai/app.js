const STORAGE_KEY = "agent-pulse-board.v1";

const STATUS = {
  RUNNING: "running",
  WAITING: "waiting",
  BLOCKED: "blocked",
  IDLE: "idle",
  DONE: "done",
};

const STATUS_LABELS = {
  [STATUS.RUNNING]: "Running",
  [STATUS.WAITING]: "Waiting You",
  [STATUS.BLOCKED]: "Blocked",
  [STATUS.IDLE]: "Idle",
  [STATUS.DONE]: "Done",
};

const STATUS_SEQUENCE = [
  STATUS.RUNNING,
  STATUS.WAITING,
  STATUS.BLOCKED,
  STATUS.IDLE,
  STATUS.DONE,
];

const nowIso = () => new Date().toISOString();
const createId = () => {
  if (globalThis.crypto?.randomUUID) return crypto.randomUUID();
  return "agent-" + Date.now() + "-" + Math.random().toString(36).slice(2, 9);
};

const createDefaultStore = () => ({
  agents: [
    {
      id: "codex",
      name: "Codex",
      source: "Desktop app",
      url: "",
      manualStatus: STATUS.IDLE,
      lastEventAt: nowIso(),
      note: "",
    },
    {
      id: "cursor",
      name: "Cursor",
      source: "Desktop IDE",
      url: "",
      manualStatus: STATUS.IDLE,
      lastEventAt: nowIso(),
      note: "",
    },
    {
      id: "lovable",
      name: "Lovable",
      source: "Browser tab",
      url: "https://lovable.dev",
      manualStatus: STATUS.IDLE,
      lastEventAt: nowIso(),
      note: "",
    },
  ],
  settings: {
    actionableOnly: false,
    blockedMinutes: 30,
    notificationsEnabled: false,
  },
});

const dom = {
  board: document.querySelector("#board"),
  quickStats: document.querySelector("#quickStats"),
  actionableOnly: document.querySelector("#actionableOnly"),
  blockedMinutes: document.querySelector("#blockedMinutes"),
  notifyBtn: document.querySelector("#notifyBtn"),
  exportBtn: document.querySelector("#exportBtn"),
  importInput: document.querySelector("#importInput"),
  resetBtn: document.querySelector("#resetBtn"),
  cardTemplate: document.querySelector("#agentCardTemplate"),
};

let store = loadStore();
const notifiedStates = new Map();

function loadStore() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return createDefaultStore();
    const parsed = JSON.parse(raw);
    return normalizeStore(parsed);
  } catch {
    return createDefaultStore();
  }
}

function normalizeStore(input) {
  const defaults = createDefaultStore();
  const agentsInput = Array.isArray(input?.agents) ? input.agents : defaults.agents;
  const agents = agentsInput.map((agent, i) => normalizeAgent(agent, defaults.agents[i]));

  const settings = {
    actionableOnly: Boolean(input?.settings?.actionableOnly),
    blockedMinutes: clampNumber(input?.settings?.blockedMinutes, 5, 720, 30),
    notificationsEnabled: Boolean(input?.settings?.notificationsEnabled),
  };

  return { agents, settings };
}

function normalizeAgent(agent, fallback) {
  const safeFallback = fallback || {
    id: createId(),
    name: "Unknown agent",
    source: "Manual",
    url: "",
    manualStatus: STATUS.IDLE,
    lastEventAt: nowIso(),
    note: "",
  };

  return {
    id: typeof agent?.id === "string" && agent.id ? agent.id : safeFallback.id,
    name: typeof agent?.name === "string" && agent.name ? agent.name : safeFallback.name,
    source: typeof agent?.source === "string" && agent.source ? agent.source : safeFallback.source,
    url: typeof agent?.url === "string" ? agent.url : safeFallback.url,
    manualStatus: STATUS_SEQUENCE.includes(agent?.manualStatus)
      ? agent.manualStatus
      : safeFallback.manualStatus,
    lastEventAt: isValidIso(agent?.lastEventAt) ? agent.lastEventAt : safeFallback.lastEventAt,
    note: typeof agent?.note === "string" ? agent.note : safeFallback.note,
  };
}

function isValidIso(value) {
  if (typeof value !== "string") return false;
  const t = Date.parse(value);
  return Number.isFinite(t);
}

function clampNumber(value, min, max, fallback) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.min(max, Math.max(min, parsed));
}

function persist() {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(store));
}

function getEffectiveStatus(agent) {
  const staleMs = store.settings.blockedMinutes * 60 * 1000;
  const lastTs = Date.parse(agent.lastEventAt);
  const timedOut = Number.isFinite(lastTs) && Date.now() - lastTs > staleMs;

  if (agent.manualStatus === STATUS.RUNNING && timedOut) {
    return { status: STATUS.BLOCKED, autoBlocked: true };
  }

  return { status: agent.manualStatus, autoBlocked: false };
}

function isActionable(status) {
  return status === STATUS.WAITING || status === STATUS.BLOCKED;
}

function statusColorClass(status) {
  return status;
}

function relativeTime(iso) {
  const ts = Date.parse(iso);
  if (!Number.isFinite(ts)) return "Unknown";

  const diffMs = Date.now() - ts;
  const abs = new Date(ts).toLocaleString();
  const minute = 60 * 1000;
  const hour = 60 * minute;

  let rel;
  if (diffMs < minute) rel = "just now";
  else if (diffMs < hour) rel = `${Math.floor(diffMs / minute)}m ago`;
  else rel = `${Math.floor(diffMs / hour)}h ago`;

  return `${rel} (${abs})`;
}

function maybeNotify(agent, effectiveStatus, autoBlocked) {
  const canNotify =
    store.settings.notificationsEnabled &&
    "Notification" in window &&
    Notification.permission === "granted";

  if (!canNotify) return;

  if (!isActionable(effectiveStatus)) {
    notifiedStates.delete(agent.id);
    return;
  }

  const prev = notifiedStates.get(agent.id);
  const stamp = `${effectiveStatus}:${agent.lastEventAt}:${autoBlocked ? "auto" : "manual"}`;
  if (prev === stamp) return;

  notifiedStates.set(agent.id, stamp);
  const title = `${agent.name}: ${STATUS_LABELS[effectiveStatus]}`;
  const body =
    effectiveStatus === STATUS.WAITING
      ? "Agent is waiting for your reply."
      : autoBlocked
        ? "No recent activity, auto-marked as blocked."
        : "Agent is blocked and needs intervention.";

  new Notification(title, { body, tag: `agent-${agent.id}` });
}

function renderStats(effectiveAgents) {
  const counts = {
    [STATUS.WAITING]: 0,
    [STATUS.BLOCKED]: 0,
    [STATUS.RUNNING]: 0,
    [STATUS.DONE]: 0,
  };

  for (const item of effectiveAgents) {
    if (counts[item.status] !== undefined) counts[item.status] += 1;
  }

  dom.quickStats.innerHTML = [
    `Waiting ${counts.waiting}`,
    `Blocked ${counts.blocked}`,
    `Running ${counts.running}`,
    `Done ${counts.done}`,
  ]
    .map((text) => `<span class="stat-pill">${text}</span>`)
    .join("");
}

function setAgent(id, updater) {
  store = {
    ...store,
    agents: store.agents.map((agent) => (agent.id === id ? updater(agent) : agent)),
  };
  persist();
  render();
}

function renderCard(agent, effectiveStatus, autoBlocked) {
  const frag = dom.cardTemplate.content.cloneNode(true);
  const root = frag.querySelector(".agent-card");
  const badge = frag.querySelector(".badge");

  root.classList.add(statusColorClass(effectiveStatus));
  frag.querySelector(".agent-name").textContent = agent.name;
  frag.querySelector(".agent-source").textContent = agent.source;

  badge.textContent = autoBlocked ? "Blocked (auto)" : STATUS_LABELS[effectiveStatus];
  badge.classList.add(statusColorClass(effectiveStatus));

  frag.querySelector(".last-event").textContent = relativeTime(agent.lastEventAt);
  frag.querySelector(".need-you").textContent = isActionable(effectiveStatus) ? "Yes" : "No";

  const urlInput = frag.querySelector(".agent-url");
  const openLink = frag.querySelector(".open-link");
  urlInput.value = agent.url;
  openLink.href = agent.url || "#";
  openLink.setAttribute("aria-disabled", agent.url ? "false" : "true");

  urlInput.addEventListener("change", (event) => {
    const value = event.target.value.trim();
    setAgent(agent.id, (prev) => ({ ...prev, url: value }));
  });

  const actions = frag.querySelector(".status-actions");

  for (const status of STATUS_SEQUENCE) {
    const button = document.createElement("button");
    button.type = "button";
    button.dataset.value = status;
    button.textContent = STATUS_LABELS[status];
    if (agent.manualStatus === status) button.classList.add("active");

    button.addEventListener("click", () => {
      setAgent(agent.id, (prev) => ({
        ...prev,
        manualStatus: status,
        lastEventAt: nowIso(),
      }));
    });

    actions.appendChild(button);
  }

  const notes = frag.querySelector(".agent-notes");
  notes.value = agent.note;
  notes.addEventListener("change", (event) => {
    setAgent(agent.id, (prev) => ({ ...prev, note: event.target.value }));
  });

  return frag;
}

function render() {
  dom.actionableOnly.checked = store.settings.actionableOnly;
  dom.blockedMinutes.value = String(store.settings.blockedMinutes);

  const effectiveAgents = store.agents.map((agent) => {
    const resolved = getEffectiveStatus(agent);
    return { agent, status: resolved.status, autoBlocked: resolved.autoBlocked };
  });

  renderStats(effectiveAgents);

  for (const item of effectiveAgents) {
    maybeNotify(item.agent, item.status, item.autoBlocked);
  }

  const visible = store.settings.actionableOnly
    ? effectiveAgents.filter((item) => isActionable(item.status))
    : effectiveAgents;

  dom.board.innerHTML = "";

  if (visible.length === 0) {
    dom.board.innerHTML =
      '<div class="empty-state">No actionable agents now. You can disable the filter or update agent statuses.</div>';
    return;
  }

  for (const item of visible) {
    dom.board.appendChild(renderCard(item.agent, item.status, item.autoBlocked));
  }
}

function enableNotifications() {
  if (!("Notification" in window)) {
    alert("Browser notifications are not supported in this browser.");
    return;
  }

  Notification.requestPermission().then((perm) => {
    const enabled = perm === "granted";
    store = {
      ...store,
      settings: { ...store.settings, notificationsEnabled: enabled },
    };
    persist();

    dom.notifyBtn.textContent = enabled ? "Notifications enabled" : "Enable notifications";
    render();
  });
}

function exportStore() {
  const blob = new Blob([JSON.stringify(store, null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = `agent-pulse-board-${new Date().toISOString().slice(0, 19)}.json`;
  link.click();
  URL.revokeObjectURL(url);
}

function importStore(file) {
  if (!file) return;
  const reader = new FileReader();
  reader.onload = () => {
    try {
      const parsed = JSON.parse(String(reader.result));
      store = normalizeStore(parsed);
      persist();
      render();
    } catch {
      alert("Invalid JSON file.");
    }
  };
  reader.readAsText(file);
}

function resetStore() {
  const ok = window.confirm("Reset board to default agents and settings?");
  if (!ok) return;

  store = createDefaultStore();
  persist();
  render();
}

function bindEvents() {
  dom.actionableOnly.addEventListener("change", (event) => {
    store = {
      ...store,
      settings: { ...store.settings, actionableOnly: event.target.checked },
    };
    persist();
    render();
  });

  dom.blockedMinutes.addEventListener("change", (event) => {
    const minutes = clampNumber(event.target.value, 5, 720, store.settings.blockedMinutes);
    store = {
      ...store,
      settings: { ...store.settings, blockedMinutes: minutes },
    };
    persist();
    render();
  });

  dom.notifyBtn.addEventListener("click", enableNotifications);
  dom.exportBtn.addEventListener("click", exportStore);
  dom.importInput.addEventListener("change", (event) => {
    importStore(event.target.files?.[0]);
    event.target.value = "";
  });
  dom.resetBtn.addEventListener("click", resetStore);
}

function init() {
  bindEvents();

  if (store.settings.notificationsEnabled && "Notification" in window && Notification.permission === "granted") {
    dom.notifyBtn.textContent = "Notifications enabled";
  }

  if ("serviceWorker" in navigator) {
    navigator.serviceWorker.register("./sw.js").catch(() => {
      // Ignore service worker errors for local-file usage.
    });
  }

  render();
  setInterval(render, 30_000);
}

init();
