import React, { useState } from 'react';
import { motion } from 'motion/react';
import { ChevronLeft, Briefcase, GraduationCap, DollarSign, Heart, Brain, CheckCircle2, Plus, TrendingUp, AlertCircle, Sparkles, ListPlus } from 'lucide-react';

interface ComparisonBreakdownScreenProps {
  onBack: () => void;
  onNavigate?: (screen: string) => void;
}

type Category = 'Career' | 'Learning' | 'Finance' | 'Impact' | 'Mindset';

interface Achievement {
  id: string;
  title: string;
  date: string;
  age?: number;
}

const categories = {
  Career: { icon: <Briefcase className="w-5 h-5" />, color: '#7B61FF' },
  Learning: { icon: <GraduationCap className="w-5 h-5" />, color: '#4ADE80' },
  Finance: { icon: <DollarSign className="w-5 h-5" />, color: '#FBBF24' },
  Impact: { icon: <Heart className="w-5 h-5" />, color: '#F472B6' },
  Mindset: { icon: <Brain className="w-5 h-5" />, color: '#A78BFA' },
};

// Mock data
const mockData = {
  category: 'Finance' as Category,
  progress: 45, // percentage
  userAchievements: [
    { id: '1', title: 'Saved $10,000 emergency fund', date: 'Mar 2024', age: 28 },
    { id: '2', title: 'Started investing in index funds', date: 'Jan 2024', age: 28 },
    { id: '3', title: 'Paid off student loans', date: 'Sep 2023', age: 27 },
  ],
  idolAchievements: [
    { id: '1', title: 'Made first $1M from investments', date: '1960', age: 30 },
    { id: '2', title: 'Founded investment partnership', date: '1956', age: 26 },
    { id: '3', title: 'Bought first rental property', date: '1958', age: 28 },
    { id: '4', title: 'Started dividend portfolio', date: '1957', age: 27 },
  ],
  missingAchievements: [
    { id: '1', title: 'Start a business or side income', date: 'Suggested' },
    { id: '2', title: 'Invest in real estate', date: 'Suggested' },
    { id: '3', title: 'Build passive income stream', date: 'Suggested' },
    { id: '4', title: 'Create diversified portfolio', date: 'Suggested' },
  ],
};

export function ComparisonBreakdownScreen({ 
  onBack, 
  onNavigate
}: ComparisonBreakdownScreenProps) {
  const [selectedCategory] = useState<Category>(mockData.category);
  const categoryConfig = categories[selectedCategory];

  return (
    <div className="h-screen bg-[#121212] flex flex-col">
      {/* Header */}
      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.5 }}
        className="px-6 pt-12 pb-4 border-b border-[#2A2A2E] bg-[#121212]"
      >
        <motion.button
          whileHover={{ scale: 1.1 }}
          whileTap={{ scale: 0.9 }}
          onClick={onBack}
          className="p-2 -ml-2 mb-4"
        >
          <ChevronLeft className="w-6 h-6 text-white" />
        </motion.button>
        <h1 className="text-white text-2xl">Comparison breakdown</h1>
      </motion.div>

      {/* Category & Progress Section */}
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.1, duration: 0.5 }}
        className="px-6 py-6 border-b border-[#2A2A2E] bg-[#121212]"
      >
        {/* Category Header */}
        <div className="flex items-center gap-3 mb-4">
          <div 
            className="w-12 h-12 rounded-[16px] flex items-center justify-center"
            style={{ backgroundColor: `${categoryConfig.color}20`, border: `1px solid ${categoryConfig.color}40` }}
          >
            <div style={{ color: categoryConfig.color }}>
              {categoryConfig.icon}
            </div>
          </div>
          <div className="flex-1">
            <h2 className="text-white text-lg">{selectedCategory}</h2>
            <p className="text-[#A1A1AA] text-sm">Category comparison</p>
          </div>
          <div className="text-right">
            <div className="text-white text-xl font-medium">{mockData.progress}%</div>
            <p className="text-[#A1A1AA] text-xs">Match rate</p>
          </div>
        </div>

        {/* Progress Bar */}
        <div className="relative h-3 bg-[#1C1C1E] rounded-full overflow-hidden border border-[#2A2A2E]">
          <motion.div
            initial={{ width: 0 }}
            animate={{ width: `${mockData.progress}%` }}
            transition={{ delay: 0.3, duration: 1, ease: 'easeOut' }}
            className="absolute left-0 top-0 h-full rounded-full"
            style={{ 
              background: `linear-gradient(90deg, ${categoryConfig.color}, ${categoryConfig.color}CC)`,
              boxShadow: `0 0 12px ${categoryConfig.color}60`
            }}
          />
        </div>

        {/* Stats */}
        <div className="flex items-center justify-between mt-4">
          <div className="flex items-center gap-2">
            <CheckCircle2 className="w-4 h-4 text-[#4ADE80]" />
            <span className="text-[#A1A1AA] text-sm">{mockData.userAchievements.length} completed</span>
          </div>
          <div className="flex items-center gap-2">
            <AlertCircle className="w-4 h-4 text-[#FBBF24]" />
            <span className="text-[#A1A1AA] text-sm">{mockData.missingAchievements.length} gaps found</span>
          </div>
        </div>
      </motion.div>

      {/* Scrollable Content */}
      <div className="flex-1 overflow-y-auto px-6 py-6 pb-32">
        {/* Included for You Section */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.2, duration: 0.5 }}
          className="mb-8"
        >
          <div className="flex items-center justify-between mb-4">
            <h3 className="text-white font-medium">Included for you</h3>
            <span className="text-[#7B61FF] text-xs px-2.5 py-1 rounded-full bg-[#7B61FF]/10">
              {mockData.userAchievements.length}
            </span>
          </div>

          <div className="space-y-3">
            {mockData.userAchievements.map((achievement, index) => (
              <motion.div
                key={achievement.id}
                initial={{ opacity: 0, x: -20 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ delay: 0.3 + index * 0.1, duration: 0.4 }}
                className="bg-[#1C1C1E] rounded-[16px] p-4 border border-[#2A2A2E]"
              >
                <div className="flex items-start gap-3">
                  <div className="flex-shrink-0 w-8 h-8 rounded-full bg-[#4ADE80]/10 border border-[#4ADE80]/20 flex items-center justify-center mt-0.5">
                    <CheckCircle2 className="w-4 h-4 text-[#4ADE80]" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <h4 className="text-white mb-1">{achievement.title}</h4>
                    <div className="flex items-center gap-2 text-[#A1A1AA] text-sm">
                      <span>{achievement.date}</span>
                      {achievement.age && (
                        <>
                          <span className="text-[#2A2A2E]">•</span>
                          <span>Age {achievement.age}</span>
                        </>
                      )}
                    </div>
                  </div>
                </div>
              </motion.div>
            ))}
          </div>
        </motion.div>

        {/* Idol Milestones Section */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.4, duration: 0.5 }}
          className="mb-8"
        >
          <div className="flex items-center justify-between mb-4">
            <div>
              <h3 className="text-white font-medium">Idol milestones at your age</h3>
              <p className="text-[#A1A1AA] text-xs mt-1">Warren Buffett by age 28</p>
            </div>
            <span className="text-[#7B61FF] text-xs px-2.5 py-1 rounded-full bg-[#7B61FF]/10">
              {mockData.idolAchievements.length}
            </span>
          </div>

          <div className="space-y-3">
            {mockData.idolAchievements.map((achievement, index) => (
              <motion.div
                key={achievement.id}
                initial={{ opacity: 0, x: -20 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ delay: 0.5 + index * 0.1, duration: 0.4 }}
                className="bg-[#1C1C1E] rounded-[16px] p-4 border border-[#2A2A2E]"
              >
                <div className="flex items-start gap-3">
                  <div 
                    className="flex-shrink-0 w-8 h-8 rounded-full flex items-center justify-center mt-0.5"
                    style={{ 
                      backgroundColor: `${categoryConfig.color}20`,
                      border: `1px solid ${categoryConfig.color}40`
                    }}
                  >
                    <TrendingUp className="w-4 h-4" style={{ color: categoryConfig.color }} />
                  </div>
                  <div className="flex-1 min-w-0">
                    <h4 className="text-white mb-1">{achievement.title}</h4>
                    <div className="flex items-center gap-2 text-[#A1A1AA] text-sm">
                      <span>{achievement.date}</span>
                      {achievement.age && (
                        <>
                          <span className="text-[#2A2A2E]">•</span>
                          <span>Age {achievement.age}</span>
                        </>
                      )}
                    </div>
                  </div>
                </div>
              </motion.div>
            ))}
          </div>
        </motion.div>

        {/* Missing Achievements Section */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.6, duration: 0.5 }}
          className="mb-6"
        >
          <div className="flex items-center justify-between mb-4">
            <div>
              <h3 className="text-white font-medium">Missing compared to idol</h3>
              <p className="text-[#A1A1AA] text-xs mt-1">Suggested actions to close the gap</p>
            </div>
            <span className="text-[#FBBF24] text-xs px-2.5 py-1 rounded-full bg-[#FBBF24]/10">
              {mockData.missingAchievements.length}
            </span>
          </div>

          <div className="space-y-3">
            {mockData.missingAchievements.map((achievement, index) => (
              <motion.div
                key={achievement.id}
                initial={{ opacity: 0, x: -20 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ delay: 0.7 + index * 0.1, duration: 0.4 }}
                className="bg-[#1C1C1E] rounded-[16px] p-4 border border-[#2A2A2E]"
              >
                <div className="flex items-start gap-3 mb-3">
                  <div className="flex-shrink-0 w-8 h-8 rounded-full bg-[#FBBF24]/10 border border-[#FBBF24]/20 flex items-center justify-center mt-0.5">
                    <AlertCircle className="w-4 h-4 text-[#FBBF24]" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <h4 className="text-white mb-1">{achievement.title}</h4>
                    <p className="text-[#A1A1AA] text-sm">{achievement.date}</p>
                  </div>
                </div>
                
                {/* Action Buttons */}
                <div className="flex gap-2 ml-11">
                  <motion.button
                    whileHover={{ scale: 1.05 }}
                    whileTap={{ scale: 0.95 }}
                    onClick={() => {
                      console.log('Add to plan:', achievement.title);
                      onNavigate?.('plan-tracker');
                    }}
                    className="flex-1 px-3 py-2 rounded-[12px] bg-[#7B61FF] text-white text-sm font-medium flex items-center justify-center gap-1.5 hover:bg-[#8B71FF] transition-colors"
                  >
                    <ListPlus className="w-4 h-4" />
                    <span>Add to plan</span>
                  </motion.button>
                  
                  <motion.button
                    whileHover={{ scale: 1.05 }}
                    whileTap={{ scale: 0.95 }}
                    onClick={() => {
                      console.log('Log now:', achievement.title);
                      onNavigate?.('add-achievement');
                    }}
                    className="flex-1 px-3 py-2 rounded-[12px] border border-[#7B61FF]/30 text-[#7B61FF] text-sm font-medium flex items-center justify-center gap-1.5 hover:border-[#7B61FF]/50 hover:bg-[#7B61FF]/5 transition-all"
                  >
                    <Plus className="w-4 h-4" />
                    <span>Log now</span>
                  </motion.button>
                </div>
              </motion.div>
            ))}
          </div>
        </motion.div>

        {/* Info Card */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 1, duration: 0.4 }}
          className="bg-[#1C1C1E] rounded-[20px] p-4 border border-[#2A2A2E]"
        >
          <div className="flex gap-3">
            <TrendingUp className="w-5 h-5 text-[#7B61FF] flex-shrink-0 mt-0.5" />
            <div>
              <p className="text-[#A1A1AA] text-sm leading-relaxed">
                These gaps represent opportunities for growth based on your idol's journey at your current age. Use them to create actionable plans.
              </p>
            </div>
          </div>
        </motion.div>
      </div>

      {/* Bottom Sticky CTAs */}
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.8, duration: 0.5 }}
        className="absolute bottom-0 left-0 right-0 px-6 py-4 pb-8 bg-gradient-to-t from-[#121212] via-[#121212] to-transparent border-t border-[#2A2A2E]"
      >
        {/* Primary CTA - Generate Plan from Gaps */}
        <motion.button
          whileHover={{ scale: 1.02, y: -2 }}
          whileTap={{ scale: 0.98 }}
          onClick={() => onNavigate?.('plan-tracker')}
          className="w-full bg-gradient-to-r from-[#7B61FF] to-[#A78BFA] rounded-[20px] p-4 flex items-center justify-center gap-2 shadow-lg shadow-[#7B61FF]/30 hover:shadow-xl hover:shadow-[#7B61FF]/40 transition-all"
        >
          <Sparkles className="w-5 h-5 text-white" />
          <span className="text-white font-medium">Generate plan from gaps</span>
        </motion.button>
      </motion.div>
    </div>
  );
}