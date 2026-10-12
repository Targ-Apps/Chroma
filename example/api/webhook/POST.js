const DB_KEY = "chroma_example_webhooks";

function getDatabase() {
    const data = localStorage.getItem(DB_KEY);
    return data ? JSON.parse(data) : [];
}

function saveDatabase(data) {
    localStorage.setItem(DB_KEY, JSON.stringify(data));
}

export async function POST(req) {
    const records = getDatabase();
    const record = { id: Date.now(), body: req.body };
    records.push(record);
    saveDatabase(records);
    return { status: 201, data: { record } };
}
