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
// ENDPOINTS
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

// Set Discord helper username
app.post('/set_helper', (req, res) => {
    const { username } = req.body;
    
    if (!username) {
        return res.status(400).json({ error: 'Username required' });
    }
    
    helperDiscordUsername = username;
    console.log(`[Bridge] Helper set to: ${username}`);
    
    res.json({ 
        success: true, 
        helper: helperDiscordUsername 
    });
});

// Get current helper
app.get('/get_helper', (req, res) => {
    res.json({ 
        helper: helperDiscordUsername 
    });
});

// New question from game
app.post('/new_question', (req, res) => {
    const { id, name } = req.body;
    
    if (!id || !name) {
        return res.status(400).json({ error: 'ID and name required' });
    }
    
    if (!helperDiscordUsername) {
        return res.status(400).json({ error: 'No helper configured' });
    }
    
    // Check if already exists
    if (pendingQuestions.has(id)) {
        return res.json({ 
            success: false, 
            message: 'Question already exists' 
        });
    }
    
    pendingQuestions.set(id, {
        id: parseInt(id),
        name: name,
        timestamp: Date.now()
    });
    
    console.log(`[Bridge] New question #${id} from ${name}`);
    
    res.json({ 
        success: true,
        helper: helperDiscordUsername,
        question: { id, name }
    });
});

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

// Poll for accepted questions (from Lua)
app.get('/poll', (req, res) => {
    const accepted = [...acceptedQuestions];
    acceptedQuestions.length = 0; // Clear after sending
    
    res.json({ 
        accepted: accepted
    });
});

// Get pending questions (for debugging)
app.get('/pending', (req, res) => {
    res.json({
        questions: Array.from(pendingQuestions.values())
    });
});

// Check if question is already accepted
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
});

// =============================================
// CLEANUP OLD QUESTIONS (Optional)
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