const DB_KEY = "chroma_example_webhooks";

function getDatabase() {
    const data = localStorage.getItem(DB_KEY);
    return data ? JSON.parse(data) : [];
}

export async function GET(req) {
    return {
        status: 200,
        data: { message: "Webhook GET", query: req.query, records: getDatabase() },
    };
}
