import React from 'react';
import { motion } from 'motion/react';
import { ChevronLeft, ArrowRight, ChevronDown, Home as HomeIcon, Eye, TrendingUp, Trophy, FileText, Users } from 'lucide-react';

interface NavigationMapScreenProps {
  onBack: () => void;
}

// Screen node component
const ScreenNode = ({ 
  name, 
  color = '#7B61FF',
  delay = 0,
  icon 
}: { 
  name: string; 
  color?: string; 
  delay?: number;
  icon?: React.ReactNode;
}) => (
  <motion.div
    initial={{ opacity: 0, scale: 0.9 }}
    animate={{ opacity: 1, scale: 1 }}
    transition={{ delay, duration: 0.3 }}
    className="inline-flex items-center gap-2 px-4 py-2.5 rounded-[12px] border-2"
    style={{
      backgroundColor: `${color}10`,
      borderColor: `${color}60`,
    }}
  >
    {icon && (
      <div style={{ color }} className="flex-shrink-0">
        {icon}
      </div>
    )}
    <span className="text-white text-sm font-medium whitespace-nowrap">{name}</span>
  </motion.div>
);

// Arrow component
const FlowArrow = ({ delay = 0, vertical = false }: { delay?: number; vertical?: boolean }) => (
  <motion.div
    initial={{ opacity: 0 }}
    animate={{ opacity: 1 }}
    transition={{ delay, duration: 0.3 }}
    className="flex items-center justify-center"
  >
    {vertical ? (
      <ChevronDown className="w-5 h-5 text-[#7B61FF]" />
    ) : (
      <ArrowRight className="w-5 h-5 text-[#7B61FF]" />
    )}
  </motion.div>
);

// Section header component
const SectionHeader = ({ 
  title, 
  subtitle, 
  color = '#7B61FF', 
  delay = 0 
}: { 
  title: string; 
  subtitle?: string; 
  color?: string; 
  delay?: number;
}) => (
  <motion.div
    initial={{ opacity: 0, x: -20 }}
    animate={{ opacity: 1, x: 0 }}
    transition={{ delay, duration: 0.4 }}
    className="mb-4"
  >
    <div className="flex items-center gap-2 mb-1">
      <div className="w-1 h-4 rounded-full" style={{ backgroundColor: color }} />
      <h3 className="text-white font-medium">{title}</h3>
    </div>
    {subtitle && <p className="text-[#A1A1AA] text-xs ml-3">{subtitle}</p>}
  </motion.div>
);

export function NavigationMapScreen({ onBack }: NavigationMapScreenProps) {
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
        <h1 className="text-white text-2xl mb-2">Navigation Map</h1>
        <p className="text-[#A1A1AA] text-sm">
          App flow and screen connections
        </p>
      </motion.div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto px-6 py-6 space-y-8">
        {/* 1. Initial Flow */}
        <div>
          <SectionHeader 
            title="Initial Flow" 
            subtitle="First-time user experience"
            color="#7B61FF"
            delay={0.1}
          />
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.15, duration: 0.4 }}
            className="bg-[#1C1C1E] rounded-[20px] p-5 border border-[#2A2A2E]"
          >
            <div className="flex flex-col gap-2">
              <ScreenNode name="Splash" color="#7B61FF" delay={0.2} />
              <FlowArrow delay={0.25} vertical />
              <ScreenNode name="Onboarding" color="#7B61FF" delay={0.3} />
              <FlowArrow delay={0.35} vertical />
              <ScreenNode name="Idol Suggestions" color="#7B61FF" delay={0.4} />
              <FlowArrow delay={0.45} vertical />
              <ScreenNode name="Home Dashboard" color="#7B61FF" delay={0.5} icon={<HomeIcon className="w-4 h-4" />} />
            </div>
          </motion.div>
        </div>

        {/* 2. Timeline Flow */}
        <div>
          <SectionHeader 
            title="Timeline Flow" 
            subtitle="View idol's journey and evidence"
            color="#60A5FA"
            delay={0.55}
          />
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.6, duration: 0.4 }}
            className="bg-[#1C1C1E] rounded-[20px] p-5 border border-[#2A2A2E]"
          >
            <div className="flex flex-col gap-2">
              <ScreenNode name="Home Dashboard" color="#60A5FA" delay={0.65} icon={<HomeIcon className="w-4 h-4" />} />
              <FlowArrow delay={0.7} vertical />
              <ScreenNode name="Idol Timeline" color="#60A5FA" delay={0.75} icon={<Eye className="w-4 h-4" />} />
              <FlowArrow delay={0.8} vertical />
              <ScreenNode name="Evidence Sheet" color="#60A5FA" delay={0.85} />
            </div>
          </motion.div>
        </div>

        {/* 3. Comparison Flow */}
        <div>
          <SectionHeader 
            title="Comparison Flow" 
            subtitle="Compare progress and generate action plans"
            color="#FBBF24"
            delay={0.9}
          />
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.95, duration: 0.4 }}
            className="bg-[#1C1C1E] rounded-[20px] p-5 border border-[#2A2A2E]"
          >
            <div className="flex flex-col gap-2">
              <ScreenNode name="Home Dashboard" color="#FBBF24" delay={1.0} icon={<HomeIcon className="w-4 h-4" />} />
              <FlowArrow delay={1.05} vertical />
              <ScreenNode name="Comparison Details" color="#FBBF24" delay={1.1} icon={<TrendingUp className="w-4 h-4" />} />
              <FlowArrow delay={1.15} vertical />
              <ScreenNode name="Comparison Breakdown" color="#FBBF24" delay={1.2} />
              <FlowArrow delay={1.25} vertical />
              <ScreenNode name="Plan Tracker" color="#FBBF24" delay={1.3} />
            </div>
          </motion.div>
        </div>

        {/* 4. Achievement Flow */}
        <div>
          <SectionHeader 
            title="Achievement Flow" 
            subtitle="View and edit accomplishments"
            color="#4ADE80"
            delay={1.35}
          />
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 1.4, duration: 0.4 }}
            className="bg-[#1C1C1E] rounded-[20px] p-5 border border-[#2A2A2E]"
          >
            <div className="flex flex-col gap-2">
              <ScreenNode name="Home Dashboard" color="#4ADE80" delay={1.45} icon={<HomeIcon className="w-4 h-4" />} />
              <FlowArrow delay={1.5} vertical />
              <ScreenNode name="Your Achievements" color="#4ADE80" delay={1.55} icon={<Trophy className="w-4 h-4" />} />
              <FlowArrow delay={1.6} vertical />
              <ScreenNode name="Achievement Detail" color="#4ADE80" delay={1.65} />
              <FlowArrow delay={1.7} vertical />
              <ScreenNode name="Edit Achievement" color="#4ADE80" delay={1.75} />
            </div>
          </motion.div>
        </div>

        {/* 5. Notes Flow */}
        <div>
          <SectionHeader 
            title="Notes Flow" 
            subtitle="Create and manage reflections"
            color="#F472B6"
            delay={1.8}
          />
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 1.85, duration: 0.4 }}
            className="bg-[#1C1C1E] rounded-[20px] p-5 border border-[#2A2A2E]"
          >
            <div className="flex flex-col gap-2">
              <ScreenNode name="Notes List" color="#F472B6" delay={1.9} icon={<FileText className="w-4 h-4" />} />
              <FlowArrow delay={1.95} vertical />
              <ScreenNode name="Note Detail" color="#F472B6" delay={2.0} />
              <FlowArrow delay={2.05} vertical />
              <ScreenNode name="Edit Note" color="#F472B6" delay={2.1} />
            </div>
          </motion.div>
        </div>

        {/* 6. Idol Management Flow */}
        <div>
          <SectionHeader 
            title="Idol Management" 
            subtitle="Switch and discover new idols"
            color="#A78BFA"
            delay={2.15}
          />
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 2.2, duration: 0.4 }}
            className="bg-[#1C1C1E] rounded-[20px] p-5 border border-[#2A2A2E]"
          >
            <div className="flex flex-col gap-2">
              <ScreenNode name="Home Header" color="#A78BFA" delay={2.25} icon={<HomeIcon className="w-4 h-4" />} />
              <FlowArrow delay={2.3} vertical />
              <ScreenNode name="Idol Switcher" color="#A78BFA" delay={2.35} icon={<Users className="w-4 h-4" />} />
              <FlowArrow delay={2.4} vertical />
              <ScreenNode name="Add New Idol" color="#A78BFA" delay={2.45} />
              <FlowArrow delay={2.5} vertical />
              <ScreenNode name="Idol Discovery" color="#A78BFA" delay={2.55} />
            </div>
          </motion.div>
        </div>

        {/* Legend */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 2.6, duration: 0.4 }}
          className="bg-[#1C1C1E] rounded-[20px] p-5 border border-[#2A2A2E]"
        >
          <h3 className="text-white font-medium mb-4">Flow Color Legend</h3>
          <div className="grid grid-cols-2 gap-3">
            <div className="flex items-center gap-2">
              <div className="w-3 h-3 rounded-full bg-[#7B61FF]" />
              <span className="text-[#A1A1AA] text-sm">Initial Setup</span>
            </div>
            <div className="flex items-center gap-2">
              <div className="w-3 h-3 rounded-full bg-[#60A5FA]" />
              <span className="text-[#A1A1AA] text-sm">Timeline</span>
            </div>
            <div className="flex items-center gap-2">
              <div className="w-3 h-3 rounded-full bg-[#FBBF24]" />
              <span className="text-[#A1A1AA] text-sm">Comparison</span>
            </div>
            <div className="flex items-center gap-2">
              <div className="w-3 h-3 rounded-full bg-[#4ADE80]" />
              <span className="text-[#A1A1AA] text-sm">Achievements</span>
            </div>
            <div className="flex items-center gap-2">
              <div className="w-3 h-3 rounded-full bg-[#F472B6]" />
              <span className="text-[#A1A1AA] text-sm">Notes</span>
            </div>
            <div className="flex items-center gap-2">
              <div className="w-3 h-3 rounded-full bg-[#A78BFA]" />
              <span className="text-[#A1A1AA] text-sm">Idol Mgmt</span>
            </div>
          </div>
        </motion.div>

        {/* Summary Stats */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 2.65, duration: 0.4 }}
          className="bg-[#1C1C1E] rounded-[20px] p-5 border border-[#2A2A2E]"
        >
          <h3 className="text-white font-medium mb-4">App Summary</h3>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <p className="text-[#7B61FF] text-2xl font-bold mb-1">20+</p>
              <p className="text-[#A1A1AA] text-xs">Total Screens</p>
            </div>
            <div>
              <p className="text-[#60A5FA] text-2xl font-bold mb-1">6</p>
              <p className="text-[#A1A1AA] text-xs">Main Flows</p>
            </div>
            <div>
              <p className="text-[#4ADE80] text-2xl font-bold mb-1">5</p>
              <p className="text-[#A1A1AA] text-xs">Bottom Tabs</p>
            </div>
            <div>
              <p className="text-[#FBBF24] text-2xl font-bold mb-1">15+</p>
              <p className="text-[#A1A1AA] text-xs">Components</p>
            </div>
          </div>
        </motion.div>

        {/* Bottom Padding */}
        <div className="h-6" />
      </div>
    </div>
  );
}
