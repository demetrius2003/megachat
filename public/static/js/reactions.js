// Модуль для работы с реакциями
class ReactionManager {
    constructor() {
        this.reactionPicker = null;
        this.currentOutsideClickHandler = null;
    }

    // Показ пикера реакций
    showReactionPicker(messageId) {
        console.log('🎭 Показываем пикер реакций для сообщения:', messageId);
        this.hideReactionPicker();
        
        this.reactionPicker = document.createElement('div');
        this.reactionPicker.className = 'reaction-picker';
        this.reactionPicker.id = `reaction-picker-${messageId}`;
        
        // Принудительно применяем стили
        this.reactionPicker.style.position = 'absolute';
        this.reactionPicker.style.bottom = '100%';
        this.reactionPicker.style.right = '0';
        this.reactionPicker.style.background = 'white';
        this.reactionPicker.style.border = '1px solid #dee2e6';
        this.reactionPicker.style.borderRadius = '0.5rem';
        this.reactionPicker.style.padding = '0.5rem';
        this.reactionPicker.style.boxShadow = '0 0.5rem 1rem rgba(0, 0, 0, 0.15)';
        this.reactionPicker.style.zIndex = '1000';
        this.reactionPicker.style.display = 'block';
        this.reactionPicker.style.maxWidth = '300px';
        this.reactionPicker.style.maxHeight = '200px';
        this.reactionPicker.style.overflowY = 'auto';
        
        console.log('🎭 Создан пикер реакций с принудительными стилями');
        
        const emojis = ['😀', '😃', '😄', '😁', '😆', '😂', '😊', '😍', '🤔', '😎', '😴', '😢', '👍', '👎', '👌', '✌️', '🤝', '👏', '🙌', '🤞', '❤️', '💙', '💚', '💛', '💜', '🖤', '🤍', '💔', '🎉', '🎊', '🎈', '🎁', '🎂', '🍰', '🌞', '🌙', '⭐', '🌟', '🌈', '☀️', '🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼'];
        
        // Создаем кнопки эмодзи
        emojis.forEach((emoji, index) => {
            const button = document.createElement('button');
            button.className = 'btn btn-sm btn-outline-secondary me-1 mb-1 emoji-reaction-btn';
            button.textContent = emoji;
            button.type = 'button';
            button.dataset.emoji = emoji;
            button.dataset.messageId = messageId;
            button.id = `reaction-btn-${messageId}-${index}`;
            
            this.reactionPicker.appendChild(button);
            console.log(`🎭 Создана кнопка ${emoji} с ID: ${button.id}`);
        });
        
        // Используем делегирование событий для обработки кликов
        this.reactionPicker.addEventListener('click', (e) => {
            const button = e.target.closest('.emoji-reaction-btn');
            if (button) {
                const emoji = button.dataset.emoji;
                const msgId = button.dataset.messageId;
                console.log(`🎭 Клик по кнопке реакции (делегирование): ${emoji}, сообщение: ${msgId}`);
                e.preventDefault();
                e.stopPropagation();
                
                // Вызываем метод с правильным контекстом
                if (window.reactionManager) {
                    window.reactionManager.addReaction(parseInt(msgId), emoji);
                } else {
                    console.error('❌ reactionManager не найден!');
                }
            }
        });
        
        const messageElement = document.querySelector(`[oncontextmenu*="${messageId}"]`);
        if (messageElement) {
            messageElement.appendChild(this.reactionPicker);
        }
        
        // Закрытие при клике вне пикера
        const outsideClickHandler = (e) => {
            // Проверяем, что клик был не по пикеру и не по его дочерним элементам
            if (this.reactionPicker && !this.reactionPicker.contains(e.target)) {
                console.log('🎭 Клик вне пикера реакций - закрываем');
                this.hideReactionPicker();
            }
        };
        
        setTimeout(() => {
            document.addEventListener('click', outsideClickHandler);
            // Сохраняем ссылку на обработчик для последующего удаления
            this.currentOutsideClickHandler = outsideClickHandler;
        }, 100);
    }

    // Скрытие пикера реакций
    hideReactionPicker() {
        console.log('🎭 Скрываем пикер реакций');
        if (this.reactionPicker) {
            this.reactionPicker.remove();
            this.reactionPicker = null;
        }
        
        // Удаляем обработчик внешних кликов
        if (this.currentOutsideClickHandler) {
            document.removeEventListener('click', this.currentOutsideClickHandler);
            this.currentOutsideClickHandler = null;
        }
    }

    // Добавление реакции
    async addReaction(messageId, emoji) {
        console.log('🎭 Добавляем реакцию:', emoji, 'к сообщению:', messageId);
        try {
            const response = await fetch(`/api/messages/${messageId}/reactions`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({ emoji })
            });
            
            if (response.ok) {
                await this.loadReactions(messageId);
            }
        } catch (error) {
            console.error('Ошибка добавления реакции:', error);
        }
        
        this.hideReactionPicker();
    }

    // Загрузка реакций
    async loadReactions(messageId) {
        try {
            const response = await fetch(`/api/messages/${messageId}/reactions`);
            if (response.ok) {
                const reactions = await response.json();
                this.renderReactions(messageId, reactions);
            }
        } catch (error) {
            console.error('Ошибка загрузки реакций:', error);
        }
    }

    // Отображение реакций
    renderReactions(messageId, reactions) {
        const container = document.getElementById(`reactions-${messageId}`);
        if (!container) return;
        
        if (reactions.length === 0) {
            container.innerHTML = '';
            return;
        }
        
        // Группируем реакции по эмодзи
        const groupedReactions = {};
        reactions.forEach(reaction => {
            if (!groupedReactions[reaction.emoji]) {
                groupedReactions[reaction.emoji] = [];
            }
            groupedReactions[reaction.emoji].push(reaction);
        });
        
        container.innerHTML = Object.entries(groupedReactions).map(([emoji, reactionList]) => {
            const count = reactionList.length;
            const hasUserReaction = reactionList.some(r => r.user_id === chatManager.currentUserId);
            
            return `
                <span class="reaction ${hasUserReaction ? 'user-reaction' : ''}" 
                      onclick="reactionManager.toggleReaction(${messageId}, '${emoji}')">
                    ${emoji} ${count}
                </span>
            `;
        }).join('');
    }

    // Переключение реакции
    async toggleReaction(messageId, emoji) {
        try {
            const response = await fetch(`/api/messages/${messageId}/reactions`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({ emoji })
            });
            
            if (response.ok) {
                await this.loadReactions(messageId);
            }
        } catch (error) {
            console.error('Ошибка переключения реакции:', error);
        }
    }
}

// Создаем глобальный экземпляр
window.reactionManager = new ReactionManager();
