window.RIFA_CONFIG = {
  campaignId: "junior-cirurgia",
  campaignTitle: "Rifa Beneficente — Ajude o Júnior em sua cirurgia",
  campaignSubtitle: "Uma ação beneficente para ajudar nos custos da cirurgia do Júnior.",
  beneficiaryName: "Júnior",

  // Estes são apenas FALLBACKS locais. A quantidade oficial, o valor por número
  // e a meta são carregados do Supabase (junior_raffle_public_state).
  fallbackTotalNumbers: 1000,
  fallbackUnitPriceCents: 1000,
  fallbackGoalCents: 1000000,

  // Prêmio oficial da rifa. Valor em centavos para manter o padrão financeiro do projeto.
  prizeValue: 20000,
  prizeText: "R$ 200 no Pix",

  // Endereço público oficial e metadados de compartilhamento.
  publicUrl: "https://luizemsaopaulo.github.io/RIFA_BENEFICENTE_CIRURGIA_JUNIOR/",
  share: {
    url: "https://luizemsaopaulo.github.io/RIFA_BENEFICENTE_CIRURGIA_JUNIOR/?v=20260909-2",
    title: "Rifa Beneficente • Ajude o Júnior",
    description: "Participe da rifa beneficente do Júnior. Número por R$ 10,00 e prêmio de R$ 200 no Pix. Sua participação ajuda nos custos da cirurgia.",
    imageUrl: "https://luizemsaopaulo.github.io/RIFA_BENEFICENTE_CIRURGIA_JUNIOR/assets/rifa-junior-compartilhar-v20260909-2.png"
  },
  drawAt: "",
  drawDateText: "A definir",
  drawTimeText: "A definir",
  instagramHandle: "",
  instagramUrl: "",
  organizerWhatsapp: "",
  beneficiaryPhoto: "assets/junior-foto-placeholder.svg",

  // Handle público da conta InfinitePay do Júnior. O símbolo $ é apenas visual.
  infinitePay: {
    handle: "antonio-junior-zzc",
    displayHandle: "$antonio-junior-zzc",
    gatewayUrl: "https://rvwrljdjdogbcukxgguw.supabase.co/functions/v1/junior-infinitepay-gateway"
  },
  personalPix: {
    key: "",
    owner: ""
  },
  admin: {
    email: "junior@gmail.com",
    authUserId: "2056972b-35bc-4b4a-9f8e-7cb883ed5bed"
  },
  supabase: {
    url: "https://rvwrljdjdogbcukxgguw.supabase.co",
    publishableKey: "sb_publishable_J1xXm79kjDKxDeHfGBW2Xw_dSqAcr6-"
  }
};

window.supabaseClient = window.supabase.createClient(
  window.RIFA_CONFIG.supabase.url,
  window.RIFA_CONFIG.supabase.publishableKey
);
