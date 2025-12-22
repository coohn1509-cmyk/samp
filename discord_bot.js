const { Client, GatewayIntentBits, ActionRowBuilder, ButtonBuilder, ButtonStyle } = require('discord.js');
const axios = require('axios');
const fs = require('fs');
const path = require('path');

// =============================================
// CONFIGURATION
// =============================================
const BRIDGE_URL = process.env.BRIDGE_URL || 'http://localhost:3000';
const POLL_INTERVAL = 2000; // 2 seconds
const SETTINGS_FILE = path.join(__dirname, 'newbie_helper_settings.json');

// Load Discord token from ENV or settings file
let DISCORD_TOKEN = process.env.DISCORD_TOKEN;

// Try to load from settings file if ENV not set
if (!DISCORD_TOKEN) {
    try {
        if (fs.existsSync(SETTINGS_FILE)) {
            const settings = JSON.parse(fs.readFileSync(SETTINGS_FILE, 'utf8'));
            DISCORD_TOKEN = settings.discord_bot_token;
            console.log('[Bot] Loaded token from settings file');
        }
    } catch (error) {
        console.error('[Bot] Error reading settings file:', error.message);
    }
}

// Validate token
if (!DISCORD_TOKEN || DISCORD_TOKEN.length < 50) {
    console.error('╔════════════════════════════════════════════════════════════╗');
    console.error('║  ERROR: Discord Bot Token Not Found                       ║');
    console.error('╠════════════════════════════════════════════════════════════╣');
    console.error('║  Please set the token using one of these methods:         ║');
    console.error('║                                                            ║');
    console.error('║  1. Environment Variable:                                 ║');
    console.error('║     export DISCORD_TOKEN="your_token_here"                ║');
    console.error('║                                                            ║');
    console.error('║  2. Settings File (newbie_helper_settings.json):          ║');
    console.error('║     Ingame: /setdiscordtoken <YOUR_BOT_TOKEN>             ║');
    console.error('║                                                            ║');
    console.error('║  Get your token from:                                     ║');
    console.error('║  https://discord.com/developers/applications              ║');
    console.error('╚════════════════════════════════════════════════════════════╝');
    process.exit(1);
}

const client = new Client({
    intents: [
        GatewayIntentBits.Guilds,
        GatewayIntentBits.DirectMessages
    ]
});

let helperUser = null;

// =============================================
// HELPER FUNCTIONS
// =============================================
async function getHelperUsername() {
    try {
        const response = await axios.get(`${BRIDGE_URL}/get_helper`);
        return response.data.helper;
    } catch (error) {
        console.error('[Bot] Error getting helper:', error.message);
        return null;
    }
}

async function findUserByUsername(username) {
    try {
        // Search in all guilds the bot is in
        for (const guild of client.guilds.cache.values()) {
            await guild.members.fetch();
            const member = guild.members.cache.find(m => 
                m.user.username === username || 
                m.user.tag === username
            );
            if (member) {
                return member.user;
            }
        }
        return null;
    } catch (error) {
        console.error('[Bot] Error finding user:', error.message);
        return null;
    }
}

async function sendQuestionDM(user, questionId, questionName) {
    try {
        const button = new ButtonBuilder()
            .setCustomId(`accept_${questionId}`)
            .setLabel('Chấp nhận câu hỏi')
            .setStyle(ButtonStyle.Success)
            .setEmoji('✅');

        const row = new ActionRowBuilder().addComponents(button);

        const message = await user.send({
            content: `🔔 **Câu hỏi mới từ Newbie Helper**\n\n` +
                     `**ID:** ${questionId}\n` +
                     `**Người hỏi:** ${questionName}\n\n` +
                     `Nhấn nút bên dưới để chấp nhận câu hỏi này.`,
            components: [row]
        });

        console.log(`[Bot] Sent DM for question #${questionId} to ${user.tag}`);
        return true;
    } catch (error) {
        console.error('[Bot] Error sending DM:', error.message);
        return false;
    }
}

// =============================================
// POLLING FOR NEW QUESTIONS
// =============================================
async function pollForQuestions() {
    if (!helperUser) {
        const username = await getHelperUsername();
        if (username && !helperUser) {
            helperUser = await findUserByUsername(username);
            if (helperUser) {
                console.log(`[Bot] Found helper user: ${helperUser.tag}`);
            }
        }
        return;
    }

    try {
        const response = await axios.get(`${BRIDGE_URL}/pending`);
        const questions = response.data.questions || [];

        for (const question of questions) {
            await sendQuestionDM(helperUser, question.id, question.name);
        }
    } catch (error) {
        // Silent fail for polling
    }
}

// =============================================
// BUTTON INTERACTION HANDLER
// =============================================
client.on('interactionCreate', async (interaction) => {
    if (!interaction.isButton()) return;

    const customId = interaction.customId;
    
    if (!customId.startsWith('accept_')) return;

    const questionId = parseInt(customId.replace('accept_', ''));
    const acceptedBy = interaction.user.username;

    try {
        // Check if question still exists
        const checkResponse = await axios.get(`${BRIDGE_URL}/check/${questionId}`);
        
        if (!checkResponse.data.pending) {
            // Question already accepted
            await interaction.update({
                content: `❌ **Câu hỏi đã được nhận**\n\nCâu hỏi #${questionId} đã được xử lý bởi người khác.`,
                components: []
            });
            return;
        }

        // Accept the question
        const response = await axios.post(`${BRIDGE_URL}/accept`, {
            id: questionId,
            by: acceptedBy
        });

        if (response.data.success) {
            // Disable button and update message
            await interaction.update({
                content: `✅ **Bạn đã nhận câu hỏi #${questionId}**\n\n` +
                         `**Người hỏi:** ${response.data.question.name}\n` +
                         `Game sẽ tự động chấp nhận câu hỏi này.`,
                components: []
            });

            console.log(`[Bot] Question #${questionId} accepted by ${acceptedBy}`);
        } else if (response.data.already_accepted) {
            await interaction.update({
                content: `❌ **Câu hỏi đã được nhận**\n\nCâu hỏi #${questionId} đã được xử lý.`,
                components: []
            });
        }
    } catch (error) {
        console.error('[Bot] Error accepting question:', error.message);
        
        await interaction.reply({
            content: '❌ Có lỗi xảy ra khi chấp nhận câu hỏi. Vui lòng thử lại.',
            ephemeral: true
        });
    }
});

// =============================================
// BOT READY
// =============================================
client.once('ready', async () => {
    console.log(`[Bot] Logged in as ${client.user.tag}`);
    console.log(`[Bot] Token loaded from: ${process.env.DISCORD_TOKEN ? 'ENV' : 'settings file'}`);
    
    // Get helper username
    const username = await getHelperUsername();
    if (username) {
        helperUser = await findUserByUsername(username);
        if (helperUser) {
            console.log(`[Bot] Helper user found: ${helperUser.tag}`);
            await helperUser.send('✅ **Newbie Helper Bot đã sẵn sàng!**\n\nBạn sẽ nhận được thông báo khi có câu hỏi mới.');
        } else {
            console.log(`[Bot] Helper username "${username}" not found in any guild`);
        }
    }

    // Start polling
    setInterval(pollForQuestions, POLL_INTERVAL);
    console.log(`[Bot] Polling started (every ${POLL_INTERVAL}ms)`);
});

// =============================================
// START BOT
// =============================================
client.login(DISCORD_TOKEN).catch(error => {
    console.error('╔════════════════════════════════════════════════════════════╗');
    console.error('║  ERROR: Failed to Login to Discord                        ║');
    console.error('╠════════════════════════════════════════════════════════════╣');
    console.error(`║  ${error.message.padEnd(58)} ║`);
    console.error('║                                                            ║');
    console.error('║  Common issues:                                           ║');
    console.error('║  1. Invalid or expired token                              ║');
    console.error('║  2. Bot not properly configured in Discord Developer      ║');
    console.error('║  3. Insufficient bot permissions                          ║');
    console.error('╚════════════════════════════════════════════════════════════╝');
    process.exit(1);
});