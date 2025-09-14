// Модуль для поллинга (fallback для WebSocket)
class PollingManager {
    constructor() {
        this.pollingInterval = null;
    }

    // Запуск поллинга
    startPolling() {
        if (this.pollingInterval) {
            clearInterval(this.pollingInterval);
        }
        
        // Используем поллинг только если WebSocket недоступен
        if (!websocketManager.websocket || websocketManager.websocket.readyState !== WebSocket.OPEN) {
            this.pollingInterval = setInterval(async () => {
                if (chatManager.currentConversationId) {
                    try {
                        const response = await fetch(`/api/conversations/${chatManager.currentConversationId}/messages/new?last_message_id=${chatManager.lastMessageId}`);
                        if (response.ok) {
                            const newMessages = await response.json();
                            if (newMessages.length > 0) {
                                // Показываем уведомления для новых сообщений
                                if (!notificationManager.isPageVisible || document.hidden) {
                                    notificationManager.showNotification(newMessages[0]);
                                    notificationManager.playNotificationSound();
                                }
                                
                                // Добавляем новые сообщения в чат
                                newMessages.forEach(message => {
                                    chatManager.addMessageToChat(message);
                                });
                                
                                chatManager.lastMessageId = newMessages[newMessages.length - 1].id;
                                chatManager.scrollToBottom();
                                await chatManager.loadConversations();
                            }
                        }
                    } catch (error) {
                        console.error('Ошибка поллинга:', error);
                    }
                }
            }, 2000);
        }
    }

    // Остановка поллинга
    stopPolling() {
        if (this.pollingInterval) {
            clearInterval(this.pollingInterval);
            this.pollingInterval = null;
        }
    }
}

// Создаем глобальный экземпляр
window.pollingManager = new PollingManager();
