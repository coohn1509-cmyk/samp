const express = require('express');
const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.json());

// =============================================
// IN-MEMORY STORAGE
// =============================================
let helperDiscordUsername = null;
const pendingQuestions = new Map(); // id -> {id, name, timestamp}
const acceptedQuestions = []; // [{id, by, timestamp}]

// =============================================
// FILE-BASED STATE (For Android Client)
// =============================================
function generateHelperJSON() {
    return {
        accepted: acceptedQuestions,
        pending: pendingQuestions.size,
        helper: helperDiscordUsername,
        timestamp: Date.now()
    };
}

// =============================================
// ENDPOINTS FOR ANDROID (GET ONLY)
// =============================================

// Health check
app.get('/health', (req, res) => {
    res.json({ 
        status: 'ok',
        helper: helperDiscordUsername,
        pending: pendingQuestions.size,
        accepted: acceptedQuestions.length
    });
});

// Signal: New question (via query string, not POST)
app.get('/signal/new_question', (req, res) => {
    const { id, name } = req.query;
    
    if (!id || !name) {
        return res.json({ error: 'Missing id or name' });
    }
    
    if (!helperDiscordUsername) {
        return res.json({ error: 'No helper configured' });
    }
    
    const questionId = parseInt(id);
    
    // Check if already exists
    if (pendingQuestions.has(questionId)) {
        return res.json({ 
            success: false, 
            message: 'Question already exists' 
        });
    }
    
    pendingQuestions.set(questionId, {
        id: questionId,
        name: decodeURIComponent(name),
        timestamp: Date.now()
    });
    
    console.log(`[Bridge] New question #${questionId} from ${name}`);
    
    res.json({ 
        success: true,
        id: questionId
    });
});

// Signal: Set helper (via query string)
app.get('/signal/set_helper', (req, res) => {
    const { username } = req.query;
    
    if (!username) {
        return res.json({ error: 'Username required' });
    }
    
    helperDiscordUsername = decodeURIComponent(username);
    console.log(`[Bridge] Helper set to: ${helperDiscordUsername}`);
    
    res.json({ 
        success: true, 
        helper: helperDiscordUsername 
    });
});

// Poll file for Android client (GET JSON file)
app.get('/poll/helper.json', (req, res) => {
    const data = generateHelperJSON();
    
    // Clear accepted after sending
    acceptedQuestions.length = 0;
    
    res.json(data);
});

// =============================================
// ENDPOINTS FOR DISCORD BOT (POST allowed)
// =============================================

// Accept question from Discord
app.post('/accept', (req, res) => {
    const { id, by } = req.body;
    
    if (!id || !by) {
        return res.status(400).json({ error: 'ID and by required' });
    }
    
    const questionId = parseInt(id);
    
    // Check if question exists
    if (!pendingQuestions.has(questionId)) {
        return res.json({ 
            success: false,
            already_accepted: true,
            message: 'Question already accepted or does not exist'
        });
    }
    
    // Remove from pending and add to accepted
    const question = pendingQuestions.get(questionId);
    pendingQuestions.delete(questionId);
    
    acceptedQuestions.push({
        id: questionId,
        name: question.name,
        by: by,
        timestamp: Date.now()
    });
    
    console.log(`[Bridge] Question #${questionId} accepted by ${by}`);
    
    res.json({ 
        success: true,
        already_accepted: false,
        question: question
    });
});

// Get pending questions (for Discord bot polling)
app.get('/pending', (req, res) => {
    res.json({
        questions: Array.from(pendingQuestions.values())
    });
});

// Check if question is still pending
app.get('/check/:id', (req, res) => {
    const id = parseInt(req.params.id);
    const isPending = pendingQuestions.has(id);
    
    res.json({
        id: id,
        pending: isPending,
        accepted: !isPending
    });
});

// =============================================
// START SERVER
// =============================================
app.listen(PORT, () => {
    console.log(`[Bridge API] Running on port ${PORT}`);
    console.log(`[Bridge API] Helper: ${helperDiscordUsername || 'Not set'}`);
    console.log(`[Bridge API] Mode: File-based polling for Android`);
});

// =============================================
// CLEANUP OLD QUESTIONS
// =============================================
setInterval(() => {
    const now = Date.now();
    const MAX_AGE = 30 * 60 * 1000; // 30 minutes
    
    for (const [id, question] of pendingQuestions.entries()) {
        if (now - question.timestamp > MAX_AGE) {
            pendingQuestions.delete(id);
            console.log(`[Bridge] Removed old question #${id}`);
        }
    }
}, 5 * 60 * 1000); // Check every 5 minutes