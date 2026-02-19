import React from 'react';
import { motion } from 'motion/react';
import { ProgressCard } from '../ProgressCard';
import { 
  Check, 
  Bell, 
  User, 
  ChevronRight, 
  Plus, 
  TrendingUp, 
  Sparkles,
  ListChecks 
} from 'lucide-react';

interface HomeDashboardProps {
  onNavigate: (screen: string) => void;
}

const categories = [
  { label: 'Career', progress: 68, color: '#7B61FF' },
  { label: 'Learning', progress: 75, color: '#60A5FA' },
  { label: 'Finance', progress: 45, color: '#34D399' },
  { label: 'Impact', progress: 52, color: '#F59E0B' },
];

const todayTasks = [
  { task: 'Read "Zero to One" - Chapter 3', completed: true },
  { task: 'Complete Python course module', completed: true },
  { task: 'Review investment portfolio', completed: false },
  { task: 'Network with industry leaders', completed: false },
];

const quickActions = [
  {
    label: 'Add Achievement',
    icon: Plus,
    screen: 'add-achievement',
    gradient: 'from-[#7B61FF]/20 to-[#A78BFA]/20',
    iconColor: 'text-[#7B61FF]',
    borderColor: 'border-[#7B61FF]/30',
  },
  {
    label: 'View Achievements',
    icon: ListChecks,
    screen: 'your-achievements',
    gradient: 'from-[#60A5FA]/20 to-[#3B82F6]/20',
    iconColor: 'text-[#60A5FA]',
    borderColor: 'border-[#60A5FA]/30',
  },
  {
    label: 'Generate Plan',
    icon: Sparkles,
    screen: 'plan-tracker',
    gradient: 'from-[#34D399]/20 to-[#10B981]/20',
    iconColor: 'text-[#34D399]',
    borderColor: 'border-[#34D399]/30',
  },
];

export function HomeDashboard({ onNavigate }: HomeDashboardProps) {
  return (
    <div className="h-screen bg-[#121212] flex flex-col overflow-hidden">
      {/* Header */}
      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.5 }}
        className="flex-shrink-0 bg-[#121212] px-6 pt-14 pb-6 border-b border-[#2A2A2E] z-10"
      >
        <div className="flex justify-between items-center mb-6">
          <div className="flex-1 min-w-0">
            <h1 className="text-white text-3xl mb-1 truncate">Dashboard</h1>
            <p className="text-[#A1A1AA] text-sm">Monday, Jan 5</p>
          </div>
          <div className="flex gap-3 flex-shrink-0 ml-4">
            <motion.button
              whileHover={{ scale: 1.1 }}
              whileTap={{ scale: 0.9 }}
              onClick={() => onNavigate('notifications')}
              className="w-10 h-10 rounded-full bg-[#1C1C1E] flex items-center justify-center border border-[#2A2A2E]"
            >
              <Bell className="w-5 h-5 text-[#A1A1AA]" />
            </motion.button>
            <motion.button
              whileHover={{ scale: 1.1 }}
              whileTap={{ scale: 0.9 }}
              onClick={() => onNavigate('profile')}
              className="w-10 h-10 rounded-full bg-[#1C1C1E] flex items-center justify-center border border-[#2A2A2E]"
            >
              <User className="w-5 h-5 text-[#A1A1AA]" />
            </motion.button>
          </div>
        </div>

        {/* Idol Selector Pill */}
        <motion.button
          initial={{ opacity: 0, scale: 0.95 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ delay: 0.2, duration: 0.4 }}
          whileHover={{ scale: 1.02, x: 4 }}
          whileTap={{ scale: 0.98 }}
          onClick={() => onNavigate('idol-suggestions')}
          className="w-full bg-gradient-to-r from-[#7B61FF]/10 to-[#A78BFA]/10 rounded-[16px] p-3 border border-[#7B61FF]/30 flex items-center justify-between hover:border-[#7B61FF]/50 transition-all"
        >
          <div className="flex items-center gap-3">
            {/* Idol Avatar */}
            <div className="w-10 h-10 rounded-full bg-gradient-to-br from-[#7B61FF] to-[#A78BFA] flex items-center justify-center text-white font-medium shadow-lg shadow-[#7B61FF]/30">
              EM
            </div>
            <div className="text-left">
              <div className="text-white text-sm font-medium">Elon Musk</div>
              <div className="text-[#A1A1AA] text-xs">Comparing at age 32</div>
            </div>
          </div>
          <ChevronRight className="w-5 h-5 text-[#7B61FF]" />
        </motion.button>
      </motion.div>

      {/* Content */}
      <div className="px-6 py-6 space-y-8 flex-1 overflow-y-auto pb-32">
        {/* Overall Progress - Now Tappable */}
        <motion.button
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.1, duration: 0.5 }}
          whileHover={{ scale: 1.02, x: 4 }}
          whileTap={{ scale: 0.98 }}
          onClick={() => onNavigate('comparison-breakdown')}
          className="w-full bg-[#1C1C1E] rounded-[24px] p-6 border border-[#2A2A2E] hover:border-[#7B61FF]/30 transition-all text-left"
        >
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-white">Overall Closeness</h2>
            <ChevronRight className="w-5 h-5 text-[#7B61FF] opacity-60" />
          </div>
          <ProgressCard label="vs. Elon Musk (Age 32)" progress={65} />
        </motion.button>

        {/* Quick Actions */}
        <div>
          <motion.h2
            initial={{ opacity: 0, x: -20 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: 0.15, duration: 0.5 }}
            className="text-white mb-4"
          >
            Quick Actions
          </motion.h2>
          <div className="grid grid-cols-3 gap-3">
            {quickActions.map((action, index) => {
              const Icon = action.icon;
              return (
                <motion.button
                  key={action.label}
                  initial={{ opacity: 0, y: 20 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ delay: 0.2 + index * 0.1, duration: 0.4 }}
                  whileHover={{ scale: 1.05, y: -4 }}
                  whileTap={{ scale: 0.95 }}
                  onClick={() => onNavigate(action.screen)}
                  className={`bg-gradient-to-br ${action.gradient} rounded-[20px] p-4 border ${action.borderColor} hover:shadow-lg transition-all`}
                >
                  <div className="flex flex-col items-center gap-2 text-center">
                    <div className={`w-12 h-12 rounded-full bg-[#1C1C1E] border ${action.borderColor} flex items-center justify-center`}>
                      <Icon className={`w-5 h-5 ${action.iconColor}`} />
                    </div>
                    <span className="text-white text-xs font-medium leading-tight">
                      {action.label}
                    </span>
                  </div>
                </motion.button>
              );
            })}
          </div>
        </div>

        {/* Category Progress - Now Tappable */}
        <div>
          <motion.h2
            initial={{ opacity: 0, x: -20 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: 0.5, duration: 0.5 }}
            className="text-white mb-4"
          >
            Categories
          </motion.h2>
          <div className="space-y-3">
            {categories.map((cat, index) => (
              <motion.button
                key={cat.label}
                initial={{ opacity: 0, x: -20 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ delay: 0.6 + index * 0.1, duration: 0.5 }}
                whileHover={{ scale: 1.02, x: 4 }}
                whileTap={{ scale: 0.98 }}
                onClick={() => onNavigate('comparison-details')}
                className="w-full bg-[#1C1C1E] rounded-[20px] p-4 border border-[#2A2A2E] hover:border-[#7B61FF]/30 transition-all text-left"
              >
                <div className="flex items-center gap-3">
                  <div className="flex-1">
                    <ProgressCard {...cat} />
                  </div>
                  <ChevronRight className="w-5 h-5 text-[#7B61FF] opacity-60 flex-shrink-0" />
                </div>
              </motion.button>
            ))}
          </div>
        </div>

        {/* Today's Plan */}
        <div>
          <motion.div
            initial={{ opacity: 0, x: -20 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: 1.0, duration: 0.5 }}
            className="flex items-center justify-between mb-4"
          >
            <h2 className="text-white">Today's Plan</h2>
            <motion.button
              whileHover={{ x: 4 }}
              onClick={() => onNavigate('plan-tracker')}
              className="text-[#7B61FF] text-sm font-medium flex items-center gap-1"
            >
              View All
              <ChevronRight className="w-4 h-4" />
            </motion.button>
          </motion.div>
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 1.1, duration: 0.5 }}
            className="bg-[#1C1C1E] rounded-[24px] p-6 border border-[#2A2A2E] space-y-4"
          >
            {todayTasks.map((item, idx) => (
              <motion.div
                key={idx}
                initial={{ opacity: 0, x: -10 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ delay: 1.2 + idx * 0.1, duration: 0.3 }}
                className="flex items-center gap-3"
              >
                <div
                  className={`w-5 h-5 rounded-full flex items-center justify-center flex-shrink-0 ${
                    item.completed ? 'bg-[#7B61FF]' : 'border-2 border-[#2A2A2E]'
                  }`}
                >
                  {item.completed && <Check className="w-3 h-3 text-white" />}
                </div>
                <span
                  className={`${
                    item.completed ? 'text-[#A1A1AA] line-through' : 'text-white'
                  }`}
                >
                  {item.task}
                </span>
              </motion.div>
            ))}
          </motion.div>
        </div>
      </div>
    </div>
  );
}