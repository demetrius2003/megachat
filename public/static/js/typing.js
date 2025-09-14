// Модуль для работы с индикаторами печати
class TypingManager {
    constructor() {
        this.typingUsers = new Set();
        this.typingTimeout = null;
    }

    // Добавление пользователя, который печатает
    addTypingUser(username) {
        this.typingUsers.add(username);
        this.updateTypingDisplay();
    }

    // Удаление пользователя, который печатает
    removeTypingUser(username) {
        this.typingUsers.delete(username);
        this.updateTypingDisplay();
    }

    // Обновление отображения индикатора печати
    updateTypingDisplay() {
        const container = document.getElementById('typingIndicator');
        if (!container) {
            const typingDiv = document.createElement('div');
            typingDiv.id = 'typingIndicator';
            typingDiv.className = 'typing-users';
            document.body.appendChild(typingDiv);
        }
        
        const typingDiv = document.getElementById('typingIndicator');
        
        if (this.typingUsers.size > 0) {
            const users = Array.from(this.typingUsers);
            let text = '';
            if (users.length === 1) {
                text = `${users[0]} печатает...`;
            } else if (users.length === 2) {
                text = `${users[0]} и ${users[1]} печатают...`;
            } else {
                text = `${users[0]} и еще ${users.length - 1} печатают...`;
            }
            typingDiv.textContent = text;
            typingDiv.style.display = 'block';
        } else {
            typingDiv.style.display = 'none';
        }
    }

    // Настройка отслеживания печати
    setupTypingIndicator() {
        const messageInput = document.getElementById('messageInput');
        if (!messageInput) return;
        
        let typingTimer = null;
        
        messageInput.addEventListener('input', () => {
            if (chatManager.currentConversationId) {
                websocketManager.sendTypingStatus(true);
                
                // Останавливаем предыдущий таймер
                if (typingTimer) {
                    clearTimeout(typingTimer);
                }
                
                // Устанавливаем новый таймер для остановки индикатора
                typingTimer = setTimeout(() => {
                    websocketManager.sendTypingStatus(false);
                }, 2000);
            }
        });
    }
}

// Создаем глобальный экземпляр
window.typingManager = new TypingManager();
