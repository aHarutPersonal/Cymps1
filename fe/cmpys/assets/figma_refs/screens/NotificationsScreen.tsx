import React, { useState } from 'react';
import { motion } from 'motion/react';
import { ChevronLeft, Bell, Target, Trophy, TrendingUp, Calendar } from 'lucide-react';

interface NotificationsScreenProps {
  onBack: () => void;
}

const notifications = [
  {
    id: '1',
    type: 'plan' as const,
    title: 'Plan item due today',
    message: 'Complete Python course module',
    time: '2 hours ago',
    unread: true,
  },
  {
    id: '2',
    type: 'achievement' as const,
    title: 'New milestone reached!',
    message: 'You completed 10 achievements this month',
    time: '5 hours ago',
    unread: true,
  },
  {
    id: '3',
    type: 'comparison' as const,
    title: 'Comparison updated',
    message: 'Your progress in Career improved by 12%',
    time: '1 day ago',
    unread: false,
  },
  {
    id: '4',
    type: 'reminder' as const,
    title: 'Daily reflection reminder',
    message: 'Take a moment to add a note about your day',
    time: '2 days ago',
    unread: false,
  },
];

const getNotificationIcon = (type: string) => {
  switch (type) {
    case 'plan':
      return { Icon: Target, color: '#7B61FF' };
    case 'achievement':
      return { Icon: Trophy, color: '#4ADE80' };
    case 'comparison':
      return { Icon: TrendingUp, color: '#60A5FA' };
    case 'reminder':
      return { Icon: Calendar, color: '#FBBF24' };
    default:
      return { Icon: Bell, color: '#A1A1AA' };
  }
};

export function NotificationsScreen({ onBack }: NotificationsScreenProps) {
  const [hasNotifications] = useState(notifications.length > 0);

  return (
    <div className="h-screen bg-[#121212] flex flex-col overflow-hidden">
      {/* Header */}
      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.5 }}
        className="flex-shrink-0 px-6 pt-14 pb-6 border-b border-[#2A2A2E]"
      >
        <motion.button
          whileHover={{ scale: 1.1 }}
          whileTap={{ scale: 0.9 }}
          onClick={onBack}
          className="p-2 -ml-2 mb-4"
        >
          <ChevronLeft className="w-6 h-6 text-white" />
        </motion.button>
        <div className="flex items-center justify-between">
          <h1 className="text-white text-2xl">Notifications</h1>
          {hasNotifications && (
            <motion.button
              whileHover={{ scale: 1.05 }}
              whileTap={{ scale: 0.95 }}
              className="text-[#7B61FF] text-sm font-medium"
            >
              Mark all read
            </motion.button>
          )}
        </div>
      </motion.div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto px-6 py-6 pb-8">
        {!hasNotifications ? (
          // Empty State
          <motion.div
            initial={{ opacity: 0, scale: 0.95 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ duration: 0.5 }}
            className="flex flex-col items-center justify-center py-16"
          >
            <div className="w-24 h-24 rounded-full bg-[#1C1C1E] border-2 border-[#2A2A2E] flex items-center justify-center mb-6">
              <Bell className="w-12 h-12 text-[#7B61FF]" />
            </div>
            <h2 className="text-white text-xl mb-3">No notifications</h2>
            <p className="text-[#A1A1AA] text-center max-w-xs">
              You're all caught up! We'll notify you about important updates.
            </p>
          </motion.div>
        ) : (
          // Notifications List
          <div className="space-y-3">
            {notifications.map((notification, idx) => {
              const { Icon, color } = getNotificationIcon(notification.type);
              return (
                <motion.button
                  key={notification.id}
                  initial={{ opacity: 0, x: -20 }}
                  animate={{ opacity: 1, x: 0 }}
                  transition={{ delay: idx * 0.05, duration: 0.4 }}
                  whileHover={{ scale: 1.02, x: 4 }}
                  whileTap={{ scale: 0.98 }}
                  className={`w-full flex items-start gap-3 p-4 rounded-[20px] border transition-all text-left ${
                    notification.unread
                      ? 'bg-[#1C1C1E] border-[#7B61FF]/30'
                      : 'bg-[#1C1C1E] border-[#2A2A2E] hover:border-[#7B61FF]/30'
                  }`}
                >
                  {/* Icon */}
                  <div
                    className="w-10 h-10 rounded-full flex items-center justify-center flex-shrink-0 mt-1"
                    style={{
                      backgroundColor: `${color}20`,
                      border: `1px solid ${color}40`,
                    }}
                  >
                    <Icon className="w-5 h-5" style={{ color }} />
                  </div>

                  {/* Content */}
                  <div className="flex-1 min-w-0">
                    <div className="flex items-start justify-between gap-2 mb-1">
                      <h3 className="text-white font-medium">{notification.title}</h3>
                      {notification.unread && (
                        <div className="w-2 h-2 rounded-full bg-[#7B61FF] flex-shrink-0 mt-1.5" />
                      )}
                    </div>
                    <p className="text-[#A1A1AA] text-sm mb-2 line-clamp-2">
                      {notification.message}
                    </p>
                    <p className="text-[#A1A1AA] text-xs">{notification.time}</p>
                  </div>
                </motion.button>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}
