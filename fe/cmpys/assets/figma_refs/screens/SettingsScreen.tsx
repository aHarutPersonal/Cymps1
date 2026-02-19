import React, { useState } from 'react';
import { motion } from 'motion/react';
import { 
  ChevronLeft, 
  ChevronRight, 
  User as UserIcon, 
  Bell, 
  Shield, 
  FileText, 
  Download, 
  Trash2,
  Info
} from 'lucide-react';

interface SettingsScreenProps {
  onBack: () => void;
}

const SettingItem = ({ 
  icon, 
  label, 
  sublabel, 
  onClick, 
  danger = false,
  delay = 0 
}: { 
  icon: React.ReactNode; 
  label: string; 
  sublabel?: string; 
  onClick?: () => void;
  danger?: boolean;
  delay?: number;
}) => (
  <motion.button
    initial={{ opacity: 0, x: -20 }}
    animate={{ opacity: 1, x: 0 }}
    transition={{ delay, duration: 0.4 }}
    whileHover={{ scale: 1.02, x: 4 }}
    whileTap={{ scale: 0.98 }}
    onClick={onClick}
    className="w-full flex items-center gap-3 p-4 bg-[#1C1C1E] rounded-[16px] border border-[#2A2A2E] hover:border-[#7B61FF]/30 transition-all text-left"
  >
    <div className={`w-10 h-10 rounded-full flex items-center justify-center flex-shrink-0 ${
      danger 
        ? 'bg-[#EF4444]/10 border border-[#EF4444]/20' 
        : 'bg-[#7B61FF]/10 border border-[#7B61FF]/20'
    }`}>
      <div className={danger ? 'text-[#EF4444]' : 'text-[#7B61FF]'}>
        {icon}
      </div>
    </div>
    <div className="flex-1 min-w-0">
      <p className={`font-medium mb-0.5 ${danger ? 'text-[#EF4444]' : 'text-white'}`}>
        {label}
      </p>
      {sublabel && (
        <p className="text-[#A1A1AA] text-sm">{sublabel}</p>
      )}
    </div>
    <ChevronRight className={`w-5 h-5 flex-shrink-0 ${
      danger ? 'text-[#EF4444]' : 'text-[#A1A1AA]'
    }`} />
  </motion.button>
);

export function SettingsScreen({ onBack }: SettingsScreenProps) {
  return (
    <div className="h-screen bg-[#121212] flex flex-col">
      {/* Header */}
      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.5 }}
        className="px-6 pt-12 pb-6 border-b border-[#2A2A2E]"
      >
        <motion.button
          whileHover={{ scale: 1.1 }}
          whileTap={{ scale: 0.9 }}
          onClick={onBack}
          className="p-2 -ml-2 mb-4"
        >
          <ChevronLeft className="w-6 h-6 text-white" />
        </motion.button>
        <h1 className="text-white text-2xl">Settings</h1>
      </motion.div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto px-6 py-6 space-y-8 pb-8">
        {/* Account Section */}
        <div>
          <motion.h2
            initial={{ opacity: 0, x: -20 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: 0.1, duration: 0.4 }}
            className="text-[#A1A1AA] text-xs font-medium uppercase tracking-wide mb-3 px-1"
          >
            Account
          </motion.h2>
          <div className="space-y-3">
            <SettingItem
              icon={<UserIcon className="w-5 h-5" />}
              label="Profile"
              sublabel="Edit name, age, and preferences"
              onClick={() => console.log('Navigate to profile')}
              delay={0.15}
            />
          </div>
        </div>

        {/* Preferences Section */}
        <div>
          <motion.h2
            initial={{ opacity: 0, x: -20 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: 0.2, duration: 0.4 }}
            className="text-[#A1A1AA] text-xs font-medium uppercase tracking-wide mb-3 px-1"
          >
            Preferences
          </motion.h2>
          <div className="space-y-3">
            <SettingItem
              icon={<Bell className="w-5 h-5" />}
              label="Notifications"
              sublabel="Manage push and email notifications"
              onClick={() => console.log('Navigate to notifications')}
              delay={0.25}
            />
          </div>
        </div>

        {/* Privacy & Security */}
        <div>
          <motion.h2
            initial={{ opacity: 0, x: -20 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: 0.3, duration: 0.4 }}
            className="text-[#A1A1AA] text-xs font-medium uppercase tracking-wide mb-3 px-1"
          >
            Privacy & Security
          </motion.h2>
          <div className="space-y-3">
            <SettingItem
              icon={<Shield className="w-5 h-5" />}
              label="Privacy & Data"
              sublabel="Control your data and privacy settings"
              onClick={() => console.log('Navigate to privacy')}
              delay={0.35}
            />
            <SettingItem
              icon={<FileText className="w-5 h-5" />}
              label="Terms & Policies"
              sublabel="View terms of service and privacy policy"
              onClick={() => console.log('Navigate to terms')}
              delay={0.4}
            />
          </div>
        </div>

        {/* About Section */}
        <div>
          <motion.h2
            initial={{ opacity: 0, x: -20 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: 0.45, duration: 0.4 }}
            className="text-[#A1A1AA] text-xs font-medium uppercase tracking-wide mb-3 px-1"
          >
            About
          </motion.h2>
          <div className="space-y-3">
            <SettingItem
              icon={<Info className="w-5 h-5" />}
              label="Sources & Citations"
              sublabel="How we source and verify information"
              onClick={() => console.log('Navigate to sources info')}
              delay={0.5}
            />
          </div>
        </div>

        {/* Info Card - AI & Evidence */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.55, duration: 0.5 }}
          className="bg-[#1C1C1E] rounded-[20px] p-5 border border-[#2A2A2E]"
        >
          <div className="flex items-start gap-3 mb-3">
            <div className="w-10 h-10 rounded-full bg-[#7B61FF]/10 border border-[#7B61FF]/20 flex items-center justify-center flex-shrink-0">
              <Info className="w-5 h-5 text-[#7B61FF]" />
            </div>
            <div>
              <h3 className="text-white font-medium mb-1">AI-Powered Insights</h3>
              <p className="text-[#A1A1AA] text-sm leading-relaxed">
                CMPYS uses AI to analyze publicly available information about successful individuals. All comparisons are based on verified sources and historical data.
              </p>
            </div>
          </div>
          <p className="text-[#A1A1AA] text-xs leading-relaxed pl-13">
            We cite sources for all idol achievements and provide evidence links when available.
          </p>
        </motion.div>

        {/* Data Management */}
        <div>
          <motion.h2
            initial={{ opacity: 0, x: -20 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: 0.6, duration: 0.4 }}
            className="text-[#A1A1AA] text-xs font-medium uppercase tracking-wide mb-3 px-1"
          >
            Data Management
          </motion.h2>
          <div className="space-y-3">
            <SettingItem
              icon={<Download className="w-5 h-5" />}
              label="Export Data"
              sublabel="Download a copy of your data"
              onClick={() => console.log('Export data')}
              delay={0.65}
            />
          </div>
        </div>

        {/* Danger Zone */}
        <div>
          <motion.h2
            initial={{ opacity: 0, x: -20 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: 0.7, duration: 0.4 }}
            className="text-[#EF4444] text-xs font-medium uppercase tracking-wide mb-3 px-1"
          >
            Danger Zone
          </motion.h2>
          <div className="space-y-3">
            <SettingItem
              icon={<Trash2 className="w-5 h-5" />}
              label="Delete Account"
              sublabel="Permanently delete your account and data"
              onClick={() => console.log('Delete account confirmation')}
              danger
              delay={0.75}
            />
          </div>
        </div>

        {/* App Version */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.8, duration: 0.5 }}
          className="text-center pt-4"
        >
          <p className="text-[#A1A1AA] text-sm">CMPYS</p>
          <p className="text-[#A1A1AA] text-xs mt-1">Version 1.0.0</p>
        </motion.div>
      </div>
    </div>
  );
}
