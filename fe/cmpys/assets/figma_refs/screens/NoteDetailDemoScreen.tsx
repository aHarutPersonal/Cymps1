import React, { useState } from 'react';
import { motion } from 'motion/react';
import { ChevronLeft } from 'lucide-react';
import { NoteDetailScreen } from './NoteDetailScreen';
import { EditNoteScreen } from './EditNoteScreen';

interface NoteDetailDemoScreenProps {
  onBack: () => void;
}

type Screen = 'menu' | 'detail' | 'edit';

export function NoteDetailDemoScreen({ onBack }: NoteDetailDemoScreenProps) {
  const [currentScreen, setCurrentScreen] = useState<Screen>('menu');

  if (currentScreen === 'detail') {
    return (
      <NoteDetailScreen
        onBack={() => setCurrentScreen('menu')}
        onEdit={() => setCurrentScreen('edit')}
        onDelete={() => {
          console.log('Note deleted');
          setCurrentScreen('menu');
        }}
        onNavigate={(screen) => console.log('Navigate to:', screen)}
      />
    );
  }

  if (currentScreen === 'edit') {
    return (
      <EditNoteScreen
        onBack={() => setCurrentScreen('detail')}
        onSave={(note) => {
          console.log('Note saved:', note);
          setCurrentScreen('detail');
        }}
      />
    );
  }

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
        <h1 className="text-white text-2xl mb-2">Note Components</h1>
        <p className="text-[#A1A1AA] text-sm">
          Demo: Note Detail & Edit Note
        </p>
      </motion.div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto px-6 py-6 space-y-4">
        {/* Option 1: View Note Detail */}
        <motion.button
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.1, duration: 0.5 }}
          whileHover={{ scale: 1.02, x: 4 }}
          whileTap={{ scale: 0.98 }}
          onClick={() => setCurrentScreen('detail')}
          className="w-full bg-[#1C1C1E] rounded-[20px] p-6 border border-[#2A2A2E] hover:border-[#7B61FF]/30 transition-all text-left"
        >
          <h3 className="text-white mb-2 font-medium">Note Detail Screen</h3>
          <p className="text-[#A1A1AA] text-sm">
            View full note with title, date/time, body text, and attachments (idol, plan item, achievement)
          </p>
        </motion.button>

        {/* Option 2: Edit Note */}
        <motion.button
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.2, duration: 0.5 }}
          whileHover={{ scale: 1.02, x: 4 }}
          whileTap={{ scale: 0.98 }}
          onClick={() => setCurrentScreen('edit')}
          className="w-full bg-[#1C1C1E] rounded-[20px] p-6 border border-[#2A2A2E] hover:border-[#7B61FF]/30 transition-all text-left"
        >
          <h3 className="text-white mb-2 font-medium">Edit Note Screen</h3>
          <p className="text-[#A1A1AA] text-sm">
            Edit existing note with pre-filled title, body, and attachments
          </p>
        </motion.button>

        {/* Info Card */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.3, duration: 0.5 }}
          className="bg-[#1C1C1E] rounded-[20px] p-4 border border-[#2A2A2E]"
        >
          <p className="text-[#A1A1AA] text-sm leading-relaxed">
            The Edit Note screen reuses the same layout as New Note but with pre-filled content. 
            The Note Detail screen shows the overflow menu with Edit/Delete actions and displays all attachments with navigation links.
          </p>
        </motion.div>
      </div>
    </div>
  );
}
