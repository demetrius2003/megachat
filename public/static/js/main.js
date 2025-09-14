// Главный модуль для инициализации приложения
class App {
    constructor() {
        this.currentUserId = null;
    }

    // Инициализация приложения
    async init() {
        try {
            console.log('Начинаем инициализацию приложения...');
            
            // Проверяем аутентификацию
            await this.checkAuth();
            
            // Инициализируем UI
            if (window.uiManager) {
                uiManager.initEventListeners();
                console.log('UI инициализирован');
            } else {
                console.error('uiManager не найден');
            }
            
            // Инициализируем NoteManager
            if (window.noteManager) {
                console.log('NoteManager инициализирован');
            } else {
                console.error('noteManager не найден');
            }
            
            if (window.typingManager) {
                typingManager.setupTypingIndicator();
                console.log('Typing manager инициализирован');
            } else {
                console.error('typingManager не найден');
            }
            
            // Подключаемся к WebSocket
            if (window.websocketManager) {
                websocketManager.connect();
                console.log('WebSocket подключен');
            } else {
                console.error('websocketManager не найден');
            }
            
            // Загружаем данные
            if (window.chatManager) {
                await chatManager.loadConversations();
                console.log('Чаты загружены');
            } else {
                console.error('chatManager не найден');
            }
            
            console.log('Приложение инициализировано');
        } catch (error) {
            console.error('Ошибка инициализации:', error);
        }
    }

    // Проверка аутентификации
    async checkAuth() {
        try {
            const response = await fetch('/api/auth/check');
            if (response.ok) {
                const data = await response.json();
                console.log('🔍 Ответ /api/auth/check:', data);
                if (data.success) {
                    // Пробуем разные варианты ID
                    const userId = data.user_id || data.user?.id || data.id;
                    console.log('🎯 Найденный userId:', userId);
                    
                    this.currentUserId = userId;
                    chatManager.currentUserId = userId;
                    
                    console.log('✅ currentUserId установлен в main.js:', userId);
                    console.log('✅ currentUserId установлен в chatManager:', chatManager.currentUserId);
                    
                    document.getElementById('username').textContent = data.username || data.user?.username;
                    
                    // Показываем админ-панель если нужно
                    if (data.is_admin || data.user?.is_admin) {
                        document.getElementById('adminLink').style.display = 'block';
                    }
                } else {
                    window.location.href = '/login';
                }
            } else {
                window.location.href = '/login';
            }
        } catch (error) {
            console.error('Ошибка проверки прав:', error);
            window.location.href = '/login';
        }
    }

    // Выход из системы
    async logout() {
        try {
            await fetch('/api/auth/logout', { method: 'POST' });
            window.location.href = '/login';
        } catch (error) {
            console.error('Logout failed:', error);
        }
    }
}

// Создаем глобальный экземпляр
window.app = new App();

// Глобальные функции для HTML onclick
window.logout = function() {
    if (window.app) {
        app.logout();
    } else {
        console.error('app не инициализирован');
    }
};

window.createChat = function() {
    if (window.searchManager) {
        searchManager.createChat();
    } else {
        console.error('searchManager не инициализирован');
    }
};

// Инициализация при загрузке страницы
document.addEventListener('DOMContentLoaded', function() {
    app.init();
});
