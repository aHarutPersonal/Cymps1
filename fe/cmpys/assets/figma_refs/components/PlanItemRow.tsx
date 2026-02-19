import React from 'react';
import { motion } from 'motion/react';
import { CheckCircle2, Circle, BookOpen, Code, Target, TrendingUp } from 'lucide-react';

interface PlanItemRowProps {
  title: string;
  type: 'book' | 'course' | 'habit' | 'project';
  status: 'completed' | 'in-progress' | 'not-started';
  progress?: number;
}

const typeIcons = {
  book: BookOpen,
  course: Code,
  habit: Target,
  project: TrendingUp,
};

const statusColors = {
  completed: 'bg-[#7B61FF] text-white',
  'in-progress': 'bg-[#7B61FF]/20 text-[#7B61FF]',
  'not-started': 'bg-[#1C1C1E] text-[#A1A1AA] border border-[#2A2A2E]',
};

const statusLabels = {
  completed: 'Done',
  'in-progress': 'In Progress',
  'not-started': 'Not Started',
};

export function PlanItemRow({ title, type, status, progress }: PlanItemRowProps) {
  const Icon = typeIcons[type];
  const isCompleted = status === 'completed';

  return (
    <motion.div
      whileHover={{ scale: 1.02, x: 4 }}
      transition={{ type: "spring", stiffness: 300, damping: 20 }}
      className="bg-[#1C1C1E] rounded-[20px] p-4 border border-[#2A2A2E] flex items-center gap-3"
    >
      <motion.div
        animate={isCompleted ? { rotate: 360 } : {}}
        transition={{ duration: 0.5 }}
        className="flex-shrink-0"
      >
        {isCompleted ? (
          <CheckCircle2 className="w-6 h-6 text-[#7B61FF]" />
        ) : (
          <Circle className="w-6 h-6 text-[#A1A1AA]" />
        )}
      </motion.div>
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2 mb-1">
          <Icon className="w-4 h-4 text-[#A1A1AA]" />
          <h4 className="text-white truncate">{title}</h4>
        </div>
        {progress !== undefined && (
          <div className="w-full h-1 bg-[#121212] rounded-full overflow-hidden mt-2">
            <motion.div
              initial={{ width: 0 }}
              animate={{ width: `${progress}%` }}
              transition={{ duration: 1, ease: "easeOut", delay: 0.2 }}
              className="h-full bg-[#7B61FF] rounded-full"
            />
          </div>
        )}
      </div>
      <motion.div
        whileHover={{ scale: 1.05 }}
        className={`px-3 py-1 rounded-full text-xs ${statusColors[status]}`}
      >
        {statusLabels[status]}
      </motion.div>
    </motion.div>
  );
}