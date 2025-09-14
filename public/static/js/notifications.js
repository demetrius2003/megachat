// Модуль для работы с уведомлениями
class NotificationManager {
    constructor() {
        this.isPageVisible = true;
        this.lastMessageCount = 0;
        this.initVisibilityListener();
    }

    // Инициализация отслеживания видимости страницы
    initVisibilityListener() {
        document.addEventListener('visibilitychange', () => {
            this.isPageVisible = !document.hidden;
        });
    }

    // Показ уведомления
    showNotification(message) {
        if (!this.isPageVisible || document.hidden) {
            this.createNotification(message);
        }
    }

    // Создание уведомления
    createNotification(message) {
        if (!('Notification' in window)) {
            console.log('Браузер не поддерживает уведомления');
            return;
        }

        if (Notification.permission === 'granted') {
            const notification = new Notification('Новое сообщение', {
                body: `${message.sender_username}: ${message.content || 'Файл или заметка'}`,
                icon: '/favicon.ico',
                tag: 'megachat-message'
            });

            notification.onclick = () => {
                window.focus();
                notification.close();
            };

            // Автоматически закрываем через 5 секунд
            setTimeout(() => {
                notification.close();
            }, 5000);
        } else if (Notification.permission !== 'denied') {
            Notification.requestPermission().then(permission => {
                if (permission === 'granted') {
                    this.createNotification(message);
                }
            });
        }
    }

    // Воспроизведение звука уведомления
    playNotificationSound() {
        try {
            const audioContext = new (window.AudioContext || window.webkitAudioContext)();
            const oscillator = audioContext.createOscillator();
            const gainNode = audioContext.createGain();
            
            oscillator.connect(gainNode);
            gainNode.connect(audioContext.destination);
            
            oscillator.frequency.setValueAtTime(800, audioContext.currentTime);
            oscillator.frequency.setValueAtTime(600, audioContext.currentTime + 0.1);
            
            gainNode.gain.setValueAtTime(0.3, audioContext.currentTime);
            gainNode.gain.exponentialRampToValueAtTime(0.01, audioContext.currentTime + 0.3);
            
            oscillator.start(audioContext.currentTime);
            oscillator.stop(audioContext.currentTime + 0.3);
        } catch (error) {
            console.log('Не удалось воспроизвести звук:', error);
        }
    }
}

// Создаем глобальный экземпляр
window.notificationManager = new NotificationManager();
