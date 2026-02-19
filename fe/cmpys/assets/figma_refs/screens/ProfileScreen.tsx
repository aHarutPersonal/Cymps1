import React from 'react';
import { motion } from 'motion/react';
import { 
  ChevronLeft, 
  ChevronRight, 
  Edit, 
  Trophy, 
  Target, 
  FileText, 
  Users,
  Settings
} from 'lucide-react';

interface ProfileScreenProps {
  onBack: () => void;
  onEditProfile?: () => void;
  onNavigate?: (screen: string) => void;
  onSwitchIdol?: () => void;
  onSettings?: () => void;
}

const quickStats = [
  { label: 'Achievements', value: '12', icon: Trophy, screen: 'your-achievements' },
  { label: 'Plan Items', value: '6', icon: Target, screen: 'plan-tracker' },
  { label: 'Notes', value: '18', icon: FileText, screen: 'notes' },
];

export function ProfileScreen({ 
  onBack, 
  onEditProfile, 
  onNavigate,
  onSwitchIdol,
  onSettings
}: ProfileScreenProps) {
  const handleNavigate = (screen: string) => {
    if (onNavigate) {
      onNavigate(screen);
    }
  };

  return (
    <div className="h-screen bg-[#121212] flex flex-col overflow-hidden">
      {/* Header */}
      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.5 }}
        className="flex-shrink-0 px-6 pt-14 pb-6 border-b border-[#2A2A2E]"
      >
        <div className="flex items-center justify-between mb-4">
          <motion.button
            whileHover={{ scale: 1.1 }}
            whileTap={{ scale: 0.9 }}
            onClick={onBack}
            className="p-2 -ml-2"
          >
            <ChevronLeft className="w-6 h-6 text-white" />
          </motion.button>
          <motion.button
            whileHover={{ scale: 1.1 }}
            whileTap={{ scale: 0.9 }}
            onClick={onSettings}
            className="p-2 -mr-2"
          >
            <Settings className="w-6 h-6 text-white" />
          </motion.button>
        </div>
        <h1 className="text-white text-2xl">Profile</h1>
      </motion.div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto px-6 py-6 pb-8 space-y-6">
        {/* Profile Card */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.1, duration: 0.5 }}
          className="bg-[#1C1C1E] rounded-[24px] p-6 border border-[#2A2A2E]"
        >
          <div className="flex items-start gap-4 mb-4">
            {/* Avatar */}
            <div className="w-20 h-20 rounded-full bg-gradient-to-br from-[#7B61FF] to-[#A78BFA] flex items-center justify-center shadow-xl shadow-[#7B61FF]/30 flex-shrink-0">
              <span className="text-white text-2xl font-bold">JD</span>
            </div>

            {/* Info */}
            <div className="flex-1 min-w-0">
              <h2 className="text-white text-2xl mb-1">John Doe</h2>
              <p className="text-[#A1A1AA] mb-3">28 years old</p>
              <motion.button
                whileHover={{ scale: 1.05 }}
                whileTap={{ scale: 0.95 }}
                onClick={onEditProfile}
                className="flex items-center gap-2 px-4 py-2 bg-[#7B61FF]/10 border border-[#7B61FF]/30 rounded-[14px] text-[#7B61FF] text-sm font-medium"
              >
                <Edit className="w-4 h-4" />
                Edit Profile
              </motion.button>
            </div>
          </div>

          {/* Current Idol */}
          <div className="pt-4 border-t border-[#2A2A2E]">
            <p className="text-[#A1A1AA] text-xs mb-2">CURRENT IDOL</p>
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 rounded-full bg-gradient-to-br from-[#7B61FF] to-[#A78BFA] flex items-center justify-center">
                  <span className="text-white text-sm font-medium">EM</span>
                </div>
                <div>
                  <p className="text-white font-medium">Elon Musk</p>
                  <p className="text-[#A1A1AA] text-xs">Entrepreneur</p>
                </div>
              </div>
              <motion.button
                whileHover={{ scale: 1.05 }}
                whileTap={{ scale: 0.95 }}
                onClick={onSwitchIdol}
                className="px-4 py-2 bg-[#121212] border border-[#2A2A2E] rounded-[12px] text-[#A1A1AA] text-sm hover:border-[#7B61FF]/30 transition-all"
              >
                Switch
              </motion.button>
            </div>
          </div>
        </motion.div>

        {/* Quick Stats */}
        <div>
          <motion.h3
            initial={{ opacity: 0, x: -20 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: 0.2, duration: 0.5 }}
            className="text-white font-medium mb-3"
          >
            Your Progress
          </motion.h3>
          <div className="grid grid-cols-3 gap-3">
            {quickStats.map((stat, idx) => {
              const Icon = stat.icon;
              return (
                <motion.button
                  key={stat.label}
                  initial={{ opacity: 0, y: 20 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ delay: 0.3 + idx * 0.1, duration: 0.4 }}
                  whileHover={{ scale: 1.05, y: -4 }}
                  whileTap={{ scale: 0.95 }}
                  onClick={() => handleNavigate(stat.screen)}
                  className="bg-[#1C1C1E] rounded-[20px] p-4 border border-[#2A2A2E] hover:border-[#7B61FF]/30 transition-all"
                >
                  <Icon className="w-5 h-5 text-[#7B61FF] mb-2" />
                  <div className="text-2xl text-white font-bold mb-1">{stat.value}</div>
                  <div className="text-xs text-[#A1A1AA]">{stat.label}</div>
                </motion.button>
              );
            })}
          </div>
        </div>

        {/* Quick Links */}
        <div>
          <motion.h3
            initial={{ opacity: 0, x: -20 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: 0.5, duration: 0.5 }}
            className="text-white font-medium mb-3"
          >
            Quick Links
          </motion.h3>
          <div className="space-y-3">
            <motion.button
              initial={{ opacity: 0, x: -20 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ delay: 0.6, duration: 0.4 }}
              whileHover={{ scale: 1.02, x: 4 }}
              whileTap={{ scale: 0.98 }}
              onClick={() => handleNavigate('your-achievements')}
              className="w-full flex items-center gap-3 p-4 bg-[#1C1C1E] rounded-[16px] border border-[#2A2A2E] hover:border-[#7B61FF]/30 transition-all"
            >
              <div className="w-10 h-10 rounded-full bg-[#7B61FF]/10 border border-[#7B61FF]/20 flex items-center justify-center">
                <Trophy className="w-5 h-5 text-[#7B61FF]" />
              </div>
              <span className="flex-1 text-white text-left">My Achievements</span>
              <ChevronRight className="w-5 h-5 text-[#A1A1AA]" />
            </motion.button>

            <motion.button
              initial={{ opacity: 0, x: -20 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ delay: 0.7, duration: 0.4 }}
              whileHover={{ scale: 1.02, x: 4 }}
              whileTap={{ scale: 0.98 }}
              onClick={() => handleNavigate('plan-tracker')}
              className="w-full flex items-center gap-3 p-4 bg-[#1C1C1E] rounded-[16px] border border-[#2A2A2E] hover:border-[#7B61FF]/30 transition-all"
            >
              <div className="w-10 h-10 rounded-full bg-[#60A5FA]/10 border border-[#60A5FA]/20 flex items-center justify-center">
                <Target className="w-5 h-5 text-[#60A5FA]" />
              </div>
              <span className="flex-1 text-white text-left">My Plan</span>
              <ChevronRight className="w-5 h-5 text-[#A1A1AA]" />
            </motion.button>

            <motion.button
              initial={{ opacity: 0, x: -20 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ delay: 0.8, duration: 0.4 }}
              whileHover={{ scale: 1.02, x: 4 }}
              whileTap={{ scale: 0.98 }}
              onClick={() => handleNavigate('notes')}
              className="w-full flex items-center gap-3 p-4 bg-[#1C1C1E] rounded-[16px] border border-[#2A2A2E] hover:border-[#7B61FF]/30 transition-all"
            >
              <div className="w-10 h-10 rounded-full bg-[#34D399]/10 border border-[#34D399]/20 flex items-center justify-center">
                <FileText className="w-5 h-5 text-[#34D399]" />
              </div>
              <span className="flex-1 text-white text-left">My Notes</span>
              <ChevronRight className="w-5 h-5 text-[#A1A1AA]" />
            </motion.button>

            <motion.button
              initial={{ opacity: 0, x: -20 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ delay: 0.9, duration: 0.4 }}
              whileHover={{ scale: 1.02, x: 4 }}
              whileTap={{ scale: 0.98 }}
              onClick={onSwitchIdol}
              className="w-full flex items-center gap-3 p-4 bg-[#1C1C1E] rounded-[16px] border border-[#2A2A2E] hover:border-[#7B61FF]/30 transition-all"
            >
              <div className="w-10 h-10 rounded-full bg-[#A78BFA]/10 border border-[#A78BFA]/20 flex items-center justify-center">
                <Users className="w-5 h-5 text-[#A78BFA]" />
              </div>
              <span className="flex-1 text-white text-left">Manage Idols</span>
              <ChevronRight className="w-5 h-5 text-[#A1A1AA]" />
            </motion.button>
          </div>
        </div>

        {/* Account Info */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 1.0, duration: 0.5 }}
          className="bg-[#1C1C1E] rounded-[20px] p-4 border border-[#2A2A2E]"
        >
          <p className="text-[#A1A1AA] text-xs mb-2">ACCOUNT</p>
          <p className="text-white text-sm mb-1">john.doe@email.com</p>
          <p className="text-[#A1A1AA] text-xs">Member since January 2026</p>
        </motion.div>
      </div>
    </div>
  );
}