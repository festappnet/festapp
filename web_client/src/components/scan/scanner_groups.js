// Group by the server's order identity, never by matching names or custom answers.
export function groupScannerTickets(items) {
    const groups=new Map();
    items.forEach((item,index)=>{
        const order=item.controller.ticket?.order_id;
        const key=order==null?`ticket:${index}`:`order:${order}`;
        if(!groups.has(key))groups.set(key,{items:[]});
        groups.get(key).items.push({...item,index});
    });
    return [...groups.values()].map(group=>{
        const references=group.items.map(({controller:c})=>c.ticket?.spot_group);
        let table=null;
        if(references.every(ref=>ref?.blueprint_id!=null && ref?.id!=null && ref?.title)){
            const first=references[0];
            if(references.every(ref=>String(ref.blueprint_id)===String(first.blueprint_id)&&String(ref.id)===String(first.id)))table=first.title;
        } else if(references.every(ref=>!ref)) {
            // Older snapshots may only contain a fully labelled seat reference.
            const labels=group.items.map(({controller:c})=>c.ticket?.spot?.match(/^((?:stůl|stol|stół|table|tisch|стіл|стол)\s+.+?)\s*[·,;]\s*(?:místo|miesto|seat|platz|miejsce|місце|место)\s+\S/iu)?.[1].trim());
            if(labels[0]&&labels.every(label=>label===labels[0]))table=labels[0];
        }
        return {...group,sharedOrder:group.items.length>1,table};
    });
}
