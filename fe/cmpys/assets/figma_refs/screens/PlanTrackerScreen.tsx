import React from 'react';
import { motion } from 'motion/react';
import { PlanItemRow } from '../PlanItemRow';
import { ChevronLeft, Calendar } from 'lucide-react';

interface PlanTrackerScreenProps {
  onBack: () => void;
}

const planItems = [
  { title: 'Zero to One by Peter Thiel', type: 'book' as const, status: 'in-progress' as const, progress: 65 },
  { title: 'Python for Data Science', type: 'course' as const, status: 'in-progress' as const, progress: 45 },
  { title: 'Daily meditation', type: 'habit' as const, status: 'completed' as const, progress: 100 },
  { title: 'Build MVP for SaaS idea', type: 'project' as const, status: 'in-progress' as const, progress: 30 },
  { title: 'The Lean Startup', type: 'book' as const, status: 'not-started' as const },
  { title: 'Morning workout routine', type: 'habit' as const, status: 'completed' as const, progress: 100 },
];

export function PlanTrackerScreen({ onBack }: PlanTrackerScreenProps) {
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
        <motion.h1
          initial={{ opacity: 0, x: -20 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ delay: 0.2, duration: 0.5 }}
          className="text-white text-3xl mb-4"
        >
          My Plan
        </motion.h1>
        
        {/* Plan Summary */}
        <motion.div
          initial={{ opacity: 0, scale: 0.95 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ delay: 0.3, duration: 0.5 }}
          className="bg-[#1C1C1E] rounded-[20px] p-4 border border-[#2A2A2E]"
        >
          <div className="flex items-center gap-3 mb-3">
            <Calendar className="w-5 h-5 text-[#7B61FF]" />
            <span className="text-white">30-Day Challenge</span>
          </div>
          <div className="grid grid-cols-3 gap-4">
            <motion.div
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.4, duration: 0.3 }}
            >
              <div className="text-2xl text-white">6</div>
              <div className="text-xs text-[#A1A1AA]">Total Tasks</div>
            </motion.div>
            <motion.div
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.5, duration: 0.3 }}
            >
              <div className="text-2xl text-[#34D399]">2</div>
              <div className="text-xs text-[#A1A1AA]">Completed</div>
            </motion.div>
            <motion.div
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.6, duration: 0.3 }}
            >
              <div className="text-2xl text-[#7B61FF]">4</div>
              <div className="text-xs text-[#A1A1AA]">In Progress</div>
            </motion.div>
          </div>
        </motion.div>
      </motion.div>

      {/* Plan Items */}
      <div className="flex-1 overflow-y-auto px-6 py-6 pb-32 space-y-3">
        {planItems.map((item, idx) => (
          <motion.div
            key={idx}
            initial={{ opacity: 0, x: -20 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: 0.7 + idx * 0.1, duration: 0.4 }}
          >
            <PlanItemRow {...item} />
          </motion.div>
        ))}
      </div>
    </div>
  );
}