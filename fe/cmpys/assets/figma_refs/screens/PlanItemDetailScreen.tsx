import React, { useState } from 'react';
import { motion } from 'motion/react';
import { ChevronLeft, ExternalLink, Clock, User as UserIcon, Minus, Plus, Check, FileText, Trophy } from 'lucide-react';
import { PrimaryButton } from '../PrimaryButton';

interface PlanItemDetailScreenProps {
  onBack: () => void;
  onMarkDone?: () => void;
  onAttachToNote?: () => void;
  onAttachToAchievement?: () => void;
}

type Status = 'not-started' | 'in-progress' | 'done';

export function PlanItemDetailScreen({ 
  onBack, 
  onMarkDone,
  onAttachToNote,
  onAttachToAchievement
}: PlanItemDetailScreenProps) {
  const [status, setStatus] = useState<Status>('in-progress');
  const [progress, setProgress] = useState(65);
  const [milestones, setMilestones] = useState([
    { id: '1', text: 'Complete course introduction', done: true },
    { id: '2', text: 'Finish modules 1-5', done: true },
    { id: '3', text: 'Practice with real portfolio', done: false },
    { id: '4', text: 'Take final assessment', done: false },
  ]);

  const handleProgressChange = (delta: number) => {
    setProgress(prev => Math.max(0, Math.min(100, prev + delta)));
  };

  const toggleMilestone = (id: string) => {
    setMilestones(prev =>
      prev.map(m => m.id === id ? { ...m, done: !m.done } : m)
    );
  };

  const handleMarkDone = () => {
    setStatus('done');
    setProgress(100);
    if (onMarkDone) onMarkDone();
  };

  const getStatusColor = (s: Status) => {
    switch (s) {
      case 'done': return '#4ADE80';
      case 'in-progress': return '#7B61FF';
      case 'not-started': return '#A1A1AA';
    }
  };

  const getStatusLabel = (s: Status) => {
    switch (s) {
      case 'done': return 'Done';
      case 'in-progress': return 'In progress';
      case 'not-started': return 'Not started';
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
        <motion.button
          whileHover={{ scale: 1.1 }}
          whileTap={{ scale: 0.9 }}
          onClick={onBack}
          className="p-2 -ml-2 mb-4"
        >
          <ChevronLeft className="w-6 h-6 text-white" />
        </motion.button>

        {/* Title & Status */}
        <div className="mb-3">
          <h1 className="text-white text-2xl mb-3">
            Complete advanced investing course
          </h1>
          <div
            className="inline-flex items-center px-3 py-1.5 rounded-full text-sm font-medium"
            style={{
              backgroundColor: `${getStatusColor(status)}20`,
              color: getStatusColor(status),
              border: `1px solid ${getStatusColor(status)}40`,
            }}
          >
            {getStatusLabel(status)}
          </div>
        </div>
      </motion.div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto px-6 py-6 pb-32 space-y-6">
        {/* Progress Control */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.1, duration: 0.5 }}
          className="bg-[#1C1C1E] rounded-[20px] p-5 border border-[#2A2A2E]"
        >
          <h3 className="text-white font-medium mb-4">Progress</h3>
          
          {/* Progress Bar */}
          <div className="mb-4">
            <div className="flex items-center justify-between mb-2">
              <span className="text-[#A1A1AA] text-sm">Completion</span>
              <span className="text-[#7B61FF] font-medium">{progress}%</span>
            </div>
            <div className="h-2 bg-[#2A2A2E] rounded-full overflow-hidden">
              <motion.div
                initial={{ width: 0 }}
                animate={{ width: `${progress}%` }}
                transition={{ duration: 0.5 }}
                className="h-full bg-gradient-to-r from-[#7B61FF] to-[#A78BFA]"
              />
            </div>
          </div>

          {/* Controls */}
          <div className="flex items-center gap-3">
            <motion.button
              whileHover={{ scale: 1.05 }}
              whileTap={{ scale: 0.95 }}
              onClick={() => handleProgressChange(-5)}
              className="flex-1 flex items-center justify-center gap-2 px-4 py-3 bg-[#121212] border border-[#2A2A2E] rounded-[14px] text-[#A1A1AA] hover:border-[#7B61FF]/30 transition-all"
            >
              <Minus className="w-4 h-4" />
              <span className="text-sm font-medium">-5%</span>
            </motion.button>
            <motion.button
              whileHover={{ scale: 1.05 }}
              whileTap={{ scale: 0.95 }}
              onClick={() => handleProgressChange(5)}
              className="flex-1 flex items-center justify-center gap-2 px-4 py-3 bg-[#121212] border border-[#2A2A2E] rounded-[14px] text-white hover:border-[#7B61FF]/30 transition-all"
            >
              <Plus className="w-4 h-4" />
              <span className="text-sm font-medium">+5%</span>
            </motion.button>
          </div>
        </motion.div>

        {/* Resource Section */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.2, duration: 0.5 }}
          className="bg-[#1C1C1E] rounded-[20px] p-5 border border-[#2A2A2E]"
        >
          <h3 className="text-white font-medium mb-4">Resource</h3>
          
          <div className="space-y-3">
            {/* Link */}
            <motion.a
              href="#"
              whileHover={{ scale: 1.02, x: 4 }}
              whileTap={{ scale: 0.98 }}
              className="flex items-center gap-3 p-3 bg-[#121212] rounded-[14px] border border-[#2A2A2E] hover:border-[#7B61FF]/30 transition-all"
            >
              <div className="w-10 h-10 rounded-full bg-[#7B61FF]/10 border border-[#7B61FF]/20 flex items-center justify-center flex-shrink-0">
                <ExternalLink className="w-5 h-5 text-[#7B61FF]" />
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-white text-sm font-medium mb-0.5">Open course</p>
                <p className="text-[#A1A1AA] text-xs">coursera.org</p>
              </div>
            </motion.a>

            {/* Metadata */}
            <div className="grid grid-cols-2 gap-3">
              <div className="p-3 bg-[#121212] rounded-[14px] border border-[#2A2A2E]">
                <div className="flex items-center gap-2 mb-1">
                  <Clock className="w-4 h-4 text-[#7B61FF]" />
                  <p className="text-[#A1A1AA] text-xs">Duration</p>
                </div>
                <p className="text-white text-sm font-medium">12 weeks</p>
              </div>
              <div className="p-3 bg-[#121212] rounded-[14px] border border-[#2A2A2E]">
                <div className="flex items-center gap-2 mb-1">
                  <UserIcon className="w-4 h-4 text-[#7B61FF]" />
                  <p className="text-[#A1A1AA] text-xs">Instructor</p>
                </div>
                <p className="text-white text-sm font-medium">Yale SOM</p>
              </div>
            </div>
          </div>
        </motion.div>

        {/* Milestones */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.3, duration: 0.5 }}
          className="bg-[#1C1C1E] rounded-[20px] p-5 border border-[#2A2A2E]"
        >
          <h3 className="text-white font-medium mb-4">Milestones</h3>
          
          <div className="space-y-2">
            {milestones.map((milestone, idx) => (
              <motion.button
                key={milestone.id}
                initial={{ opacity: 0, x: -20 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ delay: 0.4 + idx * 0.05, duration: 0.3 }}
                whileHover={{ scale: 1.02, x: 4 }}
                whileTap={{ scale: 0.98 }}
                onClick={() => toggleMilestone(milestone.id)}
                className={`w-full flex items-center gap-3 p-3 rounded-[14px] border transition-all ${
                  milestone.done
                    ? 'bg-[#4ADE80]/5 border-[#4ADE80]/20'
                    : 'bg-[#121212] border-[#2A2A2E] hover:border-[#7B61FF]/30'
                }`}
              >
                <div
                  className={`w-5 h-5 rounded-full border-2 flex items-center justify-center flex-shrink-0 transition-all ${
                    milestone.done
                      ? 'bg-[#4ADE80] border-[#4ADE80]'
                      : 'border-[#2A2A2E]'
                  }`}
                >
                  {milestone.done && <Check className="w-3 h-3 text-white" />}
                </div>
                <span
                  className={`text-sm ${
                    milestone.done ? 'text-[#A1A1AA] line-through' : 'text-white'
                  }`}
                >
                  {milestone.text}
                </span>
              </motion.button>
            ))}
          </div>
        </motion.div>

        {/* Notes Area */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.5, duration: 0.5 }}
          className="bg-[#1C1C1E] rounded-[20px] p-5 border border-[#2A2A2E]"
        >
          <h3 className="text-white font-medium mb-3">Notes</h3>
          <p className="text-[#A1A1AA] text-sm leading-relaxed mb-4">
            Focus on value investing principles and long-term thinking. Compare techniques with Warren Buffett's early strategies.
          </p>

          {/* Attach Buttons */}
          <div className="flex gap-2">
            <motion.button
              whileHover={{ scale: 1.02 }}
              whileTap={{ scale: 0.98 }}
              onClick={onAttachToNote}
              className="flex-1 flex items-center justify-center gap-2 px-3 py-2.5 bg-[#121212] border border-[#2A2A2E] rounded-[14px] text-[#A1A1AA] hover:border-[#7B61FF]/30 transition-all"
            >
              <FileText className="w-4 h-4" />
              <span className="text-xs font-medium">Attach to note</span>
            </motion.button>
            <motion.button
              whileHover={{ scale: 1.02 }}
              whileTap={{ scale: 0.98 }}
              onClick={onAttachToAchievement}
              className="flex-1 flex items-center justify-center gap-2 px-3 py-2.5 bg-[#121212] border border-[#2A2A2E] rounded-[14px] text-[#A1A1AA] hover:border-[#7B61FF]/30 transition-all"
            >
              <Trophy className="w-4 h-4" />
              <span className="text-xs font-medium">Attach to achievement</span>
            </motion.button>
          </div>
        </motion.div>
      </div>

      {/* Bottom Actions */}
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.6, duration: 0.5 }}
        className="absolute bottom-0 left-0 right-0 px-6 py-4 pb-8 bg-gradient-to-t from-[#121212] via-[#121212] to-transparent border-t border-[#2A2A2E] space-y-3"
      >
        {status !== 'done' && (
          <PrimaryButton onClick={handleMarkDone}>
            Mark as done
          </PrimaryButton>
        )}
        {status === 'done' && (
          <div className="px-6 py-4 bg-[#4ADE80]/10 border border-[#4ADE80]/30 rounded-[20px] text-center">
            <p className="text-[#4ADE80] font-medium">✓ Completed</p>
          </div>
        )}
      </motion.div>
    </div>
  );
}