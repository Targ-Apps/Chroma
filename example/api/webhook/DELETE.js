const DB_KEY = "chroma_example_webhooks";

function saveDatabase(data) {
    localStorage.setItem(DB_KEY, JSON.stringify(data));
}

export async function DELETE() {
    saveDatabase([]);
    return { status: 200, data: { message: "Cleared" } };
}
