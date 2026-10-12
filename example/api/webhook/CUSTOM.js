const DB_KEY = "chroma_example_webhooks";

function getDatabase() {
    const data = localStorage.getItem(DB_KEY);
    return data ? JSON.parse(data) : [];
}

export async function CUSTOM(req, operation) {
    if (operation === "count") {
        return { status: 200, data: { count: getDatabase().length } };
    }
    return { status: 400, error: `Unknown operation: ${operation}` };
}
