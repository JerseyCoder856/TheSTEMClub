import Link from "next/link";

const pathways = [
  {
    name: "Mechanical",
    color: "border-brand-red",
    image: "https://fiverr-res.cloudinary.com/images/t_main1,q_auto,f_auto,q_auto,f_auto/gigs/140128294/original/d7baaf14beb25f58dd892dce3475852c69a9df66/do-2d-drawing-and-3d-modeling-using-autocad-and-solidworks.jpg",
    text: "Design a useful device, model it in CAD, test materials, and discover how engineering turns ideas into working prototypes.",
  },
  {
    name: "Electrical",
    color: "border-brand-yellow",
    image: "https://i.imgur.com/fLX1GB9.jpeg",
    text: "Build a light-up badge or mini alarm while learning about voltage, resistance, sensors, and safe troubleshooting.",
  },
  {
    name: "Computer Science",
    color: "border-brand-blue",
    image: "https://images.unsplash.com/photo-1515879218367-8466d910aaa4?w=1000&q=80",
    text: "Code an interactive game or robot controller, practicing logic, debugging, and software that solves real problems.",
  },
];

export default function HomePage() {
  return (
    <>
      <header className="flex min-h-20 items-center justify-between border-b border-line bg-white px-5 md:px-12">
        <Link className="flex items-center gap-3 font-extrabold text-navy-950" href="/" aria-label="The STEM Club home">
          <span className="grid size-11 place-items-center rounded-full bg-brand-blue text-sm text-white">STEM</span>
          <span className="hidden sm:inline">The STEM Club</span>
        </Link>
        <nav aria-label="Primary navigation" className="flex items-center gap-4 text-sm font-semibold text-navy-900 md:gap-8">
          <Link href="#workshops" className="hover:text-navy-800">Workshops</Link>
          <Link href="#about" className="hover:text-navy-800">About</Link>
          <Link href="#contact" className="hover:text-navy-800">Contact</Link>
          <Link href="/member/education" className="rounded-full bg-brand-red px-4 py-3 font-bold text-white hover:bg-red-700">Member learning</Link>
        </nav>
      </header>

      <main>
        <section className="relative isolate grid min-h-[620px] items-center overflow-hidden bg-navy-950 px-6 py-20 text-white md:min-h-[680px] md:grid-cols-[1.05fr_.95fr] md:px-16">
          <div className="absolute inset-0 -z-10 bg-[linear-gradient(90deg,rgba(7,31,51,.98)_0%,rgba(7,31,51,.92)_48%,rgba(7,31,51,.20)_100%),url('https://images.unsplash.com/photo-1517420704952-d9f39e95b43e?w=1600&q=85')] bg-cover bg-center" />
          <div className="max-w-3xl">
            <p className="mb-5 inline-flex rounded-full border border-white/25 bg-white/10 px-4 py-2 text-sm font-bold">Curiosity becomes capability here.</p>
            <h1 className="max-w-3xl text-5xl leading-[1.04] font-extrabold tracking-tight md:text-7xl">Building bright futures through STEM.</h1>
            <p className="mt-6 max-w-2xl text-lg leading-8 text-white/80">The STEM Club creates welcoming workshops, mentorship, and community projects that help students discover science, technology, engineering, and math with confidence.</p>
            <div className="mt-8 flex flex-wrap gap-3">
              <Link href="#workshops" className="rounded-full bg-brand-yellow px-6 py-3 font-bold text-navy-950 hover:bg-yellow-300">Explore workshops</Link>
              <Link href="mailto:jeremiah@thestemclub.net?subject=Support%20The%20STEM%20Club" className="rounded-full bg-brand-green px-6 py-3 font-bold text-navy-950 hover:bg-green-400">Support our work</Link>
            </div>
          </div>
          <div className="hidden min-h-72 md:block" aria-hidden="true" />
        </section>

        <section id="about" className="bg-surface-soft px-5 py-20 md:px-10">
          <div className="mx-auto grid max-w-6xl gap-12 md:grid-cols-[.8fr_1.2fr] md:items-center">
            <div><p className="text-sm font-extrabold tracking-wide text-navy-800">OUR FOUNDATION</p><h2 className="mt-3 text-4xl font-extrabold leading-tight text-navy-950">Big ideas need a place to begin.</h2></div>
            <div className="grid gap-4 sm:grid-cols-2">
              <article className="border-t-4 border-brand-blue bg-white p-6 shadow-sm"><h3 className="text-xl font-extrabold text-navy-950">Mission</h3><p className="mt-3 leading-7 text-muted">Make hands-on STEM learning accessible, encouraging, and practical for students ready to explore new possibilities.</p></article>
              <article className="border-t-4 border-brand-green bg-white p-6 shadow-sm"><h3 className="text-xl font-extrabold text-navy-950">Belonging</h3><p className="mt-3 leading-7 text-muted">Help every learner see themselves as a builder, problem-solver, creator, and future STEM leader.</p></article>
            </div>
          </div>
        </section>

        <section id="workshops" className="px-5 py-20 md:px-10">
          <div className="mx-auto max-w-6xl"><p className="text-sm font-extrabold tracking-wide text-navy-800">CHOOSE A PATHWAY</p><h2 className="mt-2 text-4xl font-extrabold text-navy-950">Workshops</h2>
            <div className="mt-8 grid gap-5 md:grid-cols-3">
              {pathways.map((pathway) => <article key={pathway.name} className={`overflow-hidden border border-line border-t-4 bg-white shadow-sm ${pathway.color}`}>
                <img className="aspect-[4/3] w-full object-cover" src={pathway.image} alt={`${pathway.name} STEM workshop`} loading="lazy" />
                <div className="p-6"><h3 className="text-xl font-extrabold text-navy-950">{pathway.name}</h3><p className="mt-3 leading-7 text-muted">{pathway.text}</p></div>
              </article>)}
            </div>
          </div>
        </section>

        <section id="contact" className="bg-navy-900 px-5 py-16 text-white md:px-10">
          <div className="mx-auto flex max-w-6xl flex-col gap-6 md:flex-row md:items-center md:justify-between">
            <div><p className="text-sm font-bold text-brand-yellow">START A CONVERSATION</p><h2 className="mt-2 text-3xl font-extrabold">Let’s build something useful together.</h2><p className="mt-3 max-w-2xl leading-7 text-white/75">Ask about workshops, volunteering, partnerships, or bringing hands-on STEM learning to your community.</p></div>
            <Link className="w-fit rounded-full bg-brand-yellow px-6 py-3 font-bold text-navy-950" href="mailto:jeremiah@thestemclub.net">Contact the club</Link>
          </div>
        </section>
      </main>

      <footer className="flex flex-col gap-3 border-t border-line px-5 py-7 text-sm text-muted sm:flex-row sm:items-center sm:justify-between md:px-12">
        <span>© 2026 The STEM Club. All rights reserved.</span>
        <div className="flex gap-5"><Link href="/privacy.html">Privacy policy</Link><Link href="/legal.html">Legal</Link></div>
      </footer>
    </>
  );
}
