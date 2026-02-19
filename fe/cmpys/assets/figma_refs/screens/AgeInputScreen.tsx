import React, { useState } from 'react';
import { motion } from 'motion/react';
import { ChevronLeft, Calendar, MapPin, Minus, Plus } from 'lucide-react';
import { PrimaryButton } from '../PrimaryButton';

interface AgeInputScreenProps {
  onContinue: () => void;
  onBack: () => void;
}

export function AgeInputScreen({ onContinue, onBack }: AgeInputScreenProps) {
  const [age, setAge] = useState(28);
  const [location, setLocation] = useState('');

  const handleAgeChange = (delta: number) => {
    setAge(prev => Math.max(13, Math.min(100, prev + delta)));
  };

  const canContinue = age >= 13;

  return (
    <div className="h-screen bg-[#121212] flex flex-col">
      {/* Header */}
      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.5 }}
        className="px-6 pt-12 pb-6"
      >
        <motion.button
          whileHover={{ scale: 1.1 }}
          whileTap={{ scale: 0.9 }}
          onClick={onBack}
          className="p-2 -ml-2 mb-8"
        >
          <ChevronLeft className="w-6 h-6 text-white" />
        </motion.button>

        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.1, duration: 0.5 }}
        >
          <h1 className="text-white text-3xl mb-3">Tell us your age</h1>
          <p className="text-[#A1A1AA] leading-relaxed">
            This helps us show you idols' achievements at your age and create meaningful comparisons.
          </p>
        </motion.div>
      </motion.div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto px-6 py-6 space-y-6">
        {/* Age Stepper */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.2, duration: 0.5 }}
          className="bg-[#1C1C1E] rounded-[24px] p-6 border border-[#2A2A2E]"
        >
          <div className="flex items-center gap-2 mb-6">
            <Calendar className="w-5 h-5 text-[#7B61FF]" />
            <label className="text-white font-medium">Your Age</label>
          </div>

          {/* Age Display */}
          <div className="text-center mb-6">
            <motion.div
              key={age}
              initial={{ scale: 0.9, opacity: 0 }}
              animate={{ scale: 1, opacity: 1 }}
              transition={{ type: 'spring', stiffness: 300, damping: 20 }}
              className="text-7xl font-bold mb-2"
              style={{
                background: 'linear-gradient(135deg, #7B61FF 0%, #A78BFA 100%)',
                WebkitBackgroundClip: 'text',
                WebkitTextFillColor: 'transparent',
                backgroundClip: 'text',
              }}
            >
              {age}
            </motion.div>
            <p className="text-[#A1A1AA] text-sm">years old</p>
          </div>

          {/* Stepper Controls */}
          <div className="flex items-center gap-3">
            <motion.button
              whileHover={{ scale: 1.05 }}
              whileTap={{ scale: 0.95 }}
              onClick={() => handleAgeChange(-1)}
              className="flex-1 flex items-center justify-center gap-2 px-6 py-4 bg-[#121212] border-2 border-[#2A2A2E] rounded-[16px] text-white hover:border-[#7B61FF]/30 transition-all"
            >
              <Minus className="w-5 h-5" />
            </motion.button>
            <motion.button
              whileHover={{ scale: 1.05 }}
              whileTap={{ scale: 0.95 }}
              onClick={() => handleAgeChange(1)}
              className="flex-1 flex items-center justify-center gap-2 px-6 py-4 bg-[#121212] border-2 border-[#2A2A2E] rounded-[16px] text-white hover:border-[#7B61FF]/30 transition-all"
            >
              <Plus className="w-5 h-5" />
            </motion.button>
          </div>

          {/* Quick Select */}
          <div className="mt-4 pt-4 border-t border-[#2A2A2E]">
            <p className="text-[#A1A1AA] text-xs mb-3">Quick select:</p>
            <div className="flex flex-wrap gap-2">
              {[18, 21, 25, 30, 35, 40].map((quickAge, idx) => (
                <motion.button
                  key={quickAge}
                  initial={{ opacity: 0, scale: 0.9 }}
                  animate={{ opacity: 1, scale: 1 }}
                  transition={{ delay: 0.3 + idx * 0.05, duration: 0.3 }}
                  whileHover={{ scale: 1.05 }}
                  whileTap={{ scale: 0.95 }}
                  onClick={() => setAge(quickAge)}
                  className={`px-4 py-2 rounded-[12px] text-sm font-medium transition-all ${
                    age === quickAge
                      ? 'bg-[#7B61FF]/20 border-2 border-[#7B61FF] text-white'
                      : 'bg-[#121212] border border-[#2A2A2E] text-[#A1A1AA]'
                  }`}
                >
                  {quickAge}
                </motion.button>
              ))}
            </div>
          </div>
        </motion.div>

        {/* Location (Optional) */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.4, duration: 0.5 }}
          className="bg-[#1C1C1E] rounded-[24px] p-6 border border-[#2A2A2E]"
        >
          <div className="flex items-center gap-2 mb-4">
            <MapPin className="w-5 h-5 text-[#7B61FF]" />
            <label className="text-white font-medium">Location (optional)</label>
          </div>
          <input
            type="text"
            value={location}
            onChange={(e) => setLocation(e.target.value)}
            placeholder="e.g. San Francisco, CA"
            className="w-full bg-[#121212] border border-[#2A2A2E] rounded-[16px] px-4 py-3 text-white placeholder-[#A1A1AA] focus:outline-none focus:border-[#7B61FF]/50 transition-all"
          />
          <p className="text-[#A1A1AA] text-xs mt-2 leading-relaxed">
            Helps us show relevant local events and opportunities
          </p>
        </motion.div>

        {/* Info Card */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.5, duration: 0.5 }}
          className="bg-[#1C1C1E] rounded-[20px] p-4 border border-[#2A2A2E]"
        >
          <p className="text-[#A1A1AA] text-sm leading-relaxed">
            <span className="text-white font-medium">Privacy note:</span> Your age is used only for personalized comparisons. We never share personal information.
          </p>
        </motion.div>
      </div>

      {/* Continue Button */}
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.6, duration: 0.5 }}
        className="px-6 py-4 pb-8 border-t border-[#2A2A2E]"
      >
        <PrimaryButton onClick={onContinue} disabled={!canContinue}>
          Continue
        </PrimaryButton>
      </motion.div>
    </div>
  );
}
