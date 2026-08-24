/* Authentication and member data are supplied by Supabase; no passwords or roles are stored locally. */
(() => {
  const config = window.STEM_CLUB_SUPABASE || {};
  const configured = Boolean(config.url && config.anonKey);
  const client = configured && window.supabase ? window.supabase.createClient(config.url, config.anonKey) : null;
  const path = window.location.pathname.replace(/\/$/, '') || '/';
  const isProtected = path === '/member' || path.startsWith('/member/') || path === '/admin';
  const setMessage = (text, error = false) => { const el = document.querySelector('[data-portal-message]'); if (el) { el.textContent = text; el.classList.toggle('error', error); } };
  const home = () => window.location.assign('/');
  const login = () => window.location.assign('/login');
  const setMemberLink = session => {
    document.querySelectorAll('[data-member-access]').forEach(link => {
      link.textContent = session ? 'My STEM Club' : 'Log In'; link.href = session ? '/member' : '/login';
    });
  };
  const deny = () => { window.location.replace(`/login?next=${encodeURIComponent(path)}`); };
  async function profile() { const { data, error } = await client.from('profiles').select('first_name,last_name,member_id,account_status,role,created_at').single(); if (error) throw error; return data; }
  async function boot() {
    if (!configured) { document.documentElement.classList.add('portal-unconfigured'); if (isProtected) return deny(); setMessage('Member access will be available after the secure portal is configured.'); return; }
    const { data: { session } } = await client.auth.getSession(); setMemberLink(session);
    if (isProtected && !session) return deny();
    if ((path === '/login' || path === '/signup') && session) return window.location.replace('/member');
    if (!session) return;
    let me; try { me = await profile(); } catch (error) { setMessage('We could not load your member profile. Please try again.'); return; }
    if (me.account_status !== 'active') { await client.auth.signOut(); return login(); }
    if (path === '/admin' && me.role !== 'admin') return window.location.replace('/member');
    document.querySelectorAll('[data-first-name]').forEach(el => el.textContent = me.first_name || 'Member');
    document.querySelectorAll('[data-member-id]').forEach(el => el.textContent = me.member_id || 'Pending');
    document.querySelectorAll('[data-member-name]').forEach(el => el.textContent = `${me.first_name || ''} ${me.last_name || ''}`.trim() || 'STEM Club Member');
    document.querySelectorAll('[data-initials]').forEach(el => el.textContent = `${me.first_name?.[0] || ''}${me.last_name?.[0] || ''}` || 'ST');
    const membership = await client.from('memberships').select('level,status,starts_at,ends_at').eq('profile_id', session.user.id).maybeSingle();
    document.querySelectorAll('[data-membership-level]').forEach(el => el.textContent = membership.data?.level === 'stem_club' ? 'STEM Club Member' : 'Community Member');
    document.querySelectorAll('[data-membership-status]').forEach(el => el.textContent = membership.data?.status || 'active');
  }
  document.addEventListener('DOMContentLoaded', () => {
    document.querySelectorAll('form[data-auth]').forEach(form => form.addEventListener('submit', async e => {
      e.preventDefault(); if (!client) return setMessage('Configuration is required before member access can be used.', true);
      const action = form.dataset.auth; const data = new FormData(form); const email = String(data.get('email') || '').trim(); const password = String(data.get('password') || '');
      try {
        if (action === 'signup') { const first = String(data.get('firstName') || '').trim(); const last = String(data.get('lastName') || '').trim(); const confirm = String(data.get('confirmPassword') || ''); if (!first || !last) throw new Error('Please enter your first and last name.'); if (password !== confirm) throw new Error('Passwords do not match.'); const { error } = await client.auth.signUp({ email, password, options: { data: { first_name: first, last_name: last }, emailRedirectTo: `${location.origin}/login` } }); if (error) throw error; setMessage('Check your email to confirm your account, then log in.'); form.reset(); }
        if (action === 'login') { const { error } = await client.auth.signInWithPassword({ email, password }); if (error) throw error; window.location.assign(new URLSearchParams(location.search).get('next') || '/member'); }
        if (action === 'forgot') { const { error } = await client.auth.resetPasswordForEmail(email, { redirectTo: `${location.origin}/login` }); if (error) throw error; setMessage('If an account exists, password reset instructions have been sent.'); form.reset(); }
      } catch (err) { setMessage(err.message || 'Something went wrong. Please try again.', true); }
    }));
    document.querySelectorAll('[data-logout]').forEach(button => button.addEventListener('click', async () => { if (client) await client.auth.signOut(); home(); }));
    boot();
  });
})();
