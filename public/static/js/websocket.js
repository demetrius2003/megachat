// Модуль для работы с WebSocket
class WebSocketManager {
    constructor() {
        this.websocket = null;
        this.reconnectAttempts = 0;
        this.maxReconnectAttempts = 5;
        this.isPageVisible = true;
    }

    // Подключение к WebSocket
    connect() {
        const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
        const wsUrl = `${protocol}//${window.location.host}/ws`;
        
        this.websocket = new WebSocket(wsUrl);
        
        this.websocket.onopen = (event) => {
            console.log('WebSocket подключен');
            this.reconnectAttempts = 0;
            
            // Присоединяемся к текущему чату
            if (chatManager.currentConversationId) {
                this.joinConversation(chatManager.currentConversationId);
            }
        };
        
        this.websocket.onmessage = (event) => {
            const data = JSON.parse(event.data);
            this.handleMessage(data);
        };
        
        this.websocket.onclose = (event) => {
            console.log('WebSocket отключен');
            
            // Попытка переподключения
            if (this.reconnectAttempts < this.maxReconnectAttempts) {
                this.reconnectAttempts++;
                console.log(`Попытка переподключения ${this.reconnectAttempts}/${this.maxReconnectAttempts}`);
                setTimeout(() => this.connect(), 2000 * this.reconnectAttempts);
            }
        };
        
        this.websocket.onerror = (error) => {
            console.error('WebSocket ошибка:', error);
        };
    }

    // Обработка сообщений WebSocket
    handleMessage(data) {
        switch (data.type) {
            case 'connected':
                console.log('Подключен как:', data.username);
                break;
                
            case 'new_message':
                if (data.conversation_id === chatManager.currentConversationId) {
                    // Добавляем новое сообщение в чат
                    chatManager.addMessageToChat(data.message);
                    
                    // Показываем уведомления
                    if (!this.isPageVisible || document.hidden) {
                        notificationManager.showNotification(data.message);
                        notificationManager.playNotificationSound();
                    }
                }
                
                // Обновляем список чатов
                chatManager.loadConversations();
                break;
                
            case 'user_status':
                this.updateUserStatus(data.user_id, data.username, data.status);
                break;
                
            case 'typing':
                if (data.conversation_id === chatManager.currentConversationId) {
                    this.showTypingIndicator(data.user_id, data.username, data.is_typing);
                }
                break;
                
            case 'pong':
                // Ответ на ping
                break;
        }
    }

    // Присоединение к чату
    joinConversation(conversationId) {
        if (this.websocket && this.websocket.readyState === WebSocket.OPEN) {
            this.websocket.send(JSON.stringify({
                type: 'join_conversation',
                conversation_id: conversationId
            }));
        }
    }

    // Покидание чата
    leaveConversation() {
        if (this.websocket && this.websocket.readyState === WebSocket.OPEN) {
            this.websocket.send(JSON.stringify({
                type: 'leave_conversation'
            }));
        }
    }

    // Отправка статуса печати
    sendTypingStatus(isTyping) {
        if (this.websocket && this.websocket.readyState === WebSocket.OPEN && chatManager.currentConversationId) {
            this.websocket.send(JSON.stringify({
                type: 'typing',
                conversation_id: chatManager.currentConversationId,
                is_typing: isTyping
            }));
        }
    }

    // Обновление статуса пользователя
    updateUserStatus(userId, username, status) {
        // Обновляем статус в списке чатов
        const userElements = document.querySelectorAll(`[data-user-id="${userId}"]`);
        userElements.forEach(element => {
            const statusElement = element.querySelector('.user-status');
            if (statusElement) {
                statusElement.className = `user-status ${status}`;
            }
        });
    }

    // Показ индикатора печати
    showTypingIndicator(userId, username, isTyping) {
        if (isTyping) {
            typingManager.addTypingUser(username);
        } else {
            typingManager.removeTypingUser(username);
        }
    }

    // Ping для поддержания соединения
    ping() {
        if (this.websocket && this.websocket.readyState === WebSocket.OPEN) {
            this.websocket.send(JSON.stringify({ type: 'ping' }));
        }
    }
}

// Создаем глобальный экземпляр
window.websocketManager = new WebSocketManager();
