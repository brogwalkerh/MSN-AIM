import { useEffect } from 'react';
import { initImEvents, useImStore } from '../stores/imStore';
import { useUiStore } from '../stores/uiStore';
import { TitleBar } from './chrome/TitleBar';
import { Toolbar } from './chrome/Toolbar';
import { AddressBar } from './chrome/AddressBar';
import { Sidebar } from './chrome/Sidebar';
import { StatusBar } from './chrome/StatusBar';
import { SignInScreen } from './signin/SignInScreen';
import { HomePane } from './panes/HomePane';
import { BrowserPane } from './panes/BrowserPane';
import { ChatPane } from './panes/ChatPane';
import { MailPane } from './panes/MailPane';
import { MediaPane } from './panes/MediaPane';

let eventsInitialized = false;

export function App() {
  const session = useImStore((s) => s.session);
  const activePane = useUiStore((s) => s.activePane);

  useEffect(() => {
    if (!eventsInitialized) {
      eventsInitialized = true;
      initImEvents();
    }
  }, []);

  const signedIn = session === 'online' || session === 'syncing';

  return (
    <div className="shell">
      <TitleBar title="MSN-AIM Explorer — papillon" />
      {signedIn ? (
        <>
          <Toolbar />
          <AddressBar />
          <div className="shell__body">
            <Sidebar />
            <main className="pane-host">
              {activePane === 'home' && <HomePane />}
              {activePane === 'browser' && <BrowserPane />}
              {activePane === 'chat' && <ChatPane />}
              {activePane === 'mail' && <MailPane />}
              {activePane === 'media' && <MediaPane />}
            </main>
          </div>
        </>
      ) : (
        <SignInScreen />
      )}
      <StatusBar />
    </div>
  );
}
